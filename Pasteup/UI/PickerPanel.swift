import AppKit
import Carbon.HIToolbox
import PasteupCore
import SwiftUI

/// A floating panel that takes keyboard focus without activating the app,
/// so the app the user is typing in stays frontmost and receives the paste.
final class PickerPanel: NSPanel {
	/// Return true to consume the event before it reaches the focused view.
	var keyDownHandler: ((NSEvent) -> Bool)?
	var onResignKey: (() -> Void)?
	var arrangement: PickerArrangement?

	init() {
		super.init(
			contentRect: NSRect(x: 0, y: 0, width: PickerView.size.width, height: PickerView.size.height),
			styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
			backing: .buffered,
			defer: true
		)
		isFloatingPanel = true
		level = .floating
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
		titleVisibility = .hidden
		titlebarAppearsTransparent = true
		isMovableByWindowBackground = false
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		animationBehavior = .utilityWindow
		for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
			standardWindowButton(button)?.isHidden = true
		}
	}

	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }

	override func sendEvent(_ event: NSEvent) {
		if arrangement?.handle(event) == true { return }
		if event.type == .keyDown, keyDownHandler?(event) == true {
			return
		}
		super.sendEvent(event)
	}

	override func resignKey() {
		super.resignKey()
		onResignKey?()
	}
}

/// Shows and hides the picker and translates keys into picker actions.
final class PickerController {
	private unowned let controller: AppController
	private var panel: PickerPanel?
	private var model: PickerModel?

	init(controller: AppController) {
		self.controller = controller
	}

	var isVisible: Bool {
		panel?.isVisible == true
	}

	func show() {
		guard !isVisible else { return }
		let model = PickerModel(controller: controller)
		self.model = model

		let panel = self.panel ?? makePanel()
		self.panel = panel
		let hostingView = NSHostingView(rootView: PickerView(model: model))
		// Without this, the hidden title bar's height is reserved as a safe area and added to the panel's height.
		hostingView.safeAreaRegions = []
		panel.contentView = hostingView
		panel.arrangement = PickerArrangement(panel: panel, model: model)
		center(panel)
		panel.makeKeyAndOrderFront(nil)
	}

	func close() {
		guard let panel, panel.isVisible else { return }
		panel.arrangement?.cancel()
		panel.arrangement = nil
		panel.orderOut(nil)
		panel.contentView = nil
		model = nil
	}

	/// Keeps an open picker in sync when a copy, delete, save or unsave changes a list.
	func listsDidChange() {
		model?.reload()
	}

	private func makePanel() -> PickerPanel {
		let panel = PickerPanel()
		panel.keyDownHandler = { [weak self] event in
			self?.handleKeyDown(event) ?? false
		}
		panel.onResignKey = { [weak self] in
			guard self?.panel?.arrangement?.isTracking != true else { return }
			self?.close()
		}
		return panel
	}

	/// Centered on the screen that has keyboard focus.
	private func center(_ panel: NSPanel) {
		guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
		let visible = screen.visibleFrame
		let size = panel.frame.size
		panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
	}

	private func handleKeyDown(_ event: NSEvent) -> Bool {
		guard let model else { return false }
		let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
		switch Int(event.keyCode) {
		case kVK_UpArrow:
			model.moveSelection(by: -1)
		case kVK_DownArrow:
			model.moveSelection(by: 1)
		// Plain arrows switch lists; with a modifier they still move the cursor in the filter field.
		case kVK_LeftArrow where modifiers.isEmpty:
			model.show(.history)
		case kVK_RightArrow where modifiers.isEmpty:
			model.show(.saved)
		// By character, not key code, so ⌘S follows the keyboard layout.
		case _ where modifiers == .command && event.charactersIgnoringModifiers == "s":
			toggleSavedSelection()
		case kVK_Return, kVK_ANSI_KeypadEnter:
			pasteSelection(plainText: modifiers.contains(.shift))
		case kVK_Escape:
			if model.query.isEmpty {
				close()
			} else {
				model.query = ""
			}
		case kVK_Delete where modifiers.contains(.command):
			deleteSelection()
		default:
			return false
		}
		return true
	}

	func pasteSelection(plainText: Bool) {
		guard let model, let index = model.state.selectedClipIndex else {
			NSSound.beep()
			return
		}
		controller.paste(clipAt: index, in: model.list, plainText: plainText)
	}

	private func deleteSelection() {
		guard let model, let index = model.state.selectedClipIndex else {
			NSSound.beep()
			return
		}
		controller.delete(clipAt: index, in: model.list)
	}

	private func toggleSavedSelection() {
		guard let model, let index = model.state.selectedClipIndex else {
			NSSound.beep()
			return
		}
		controller.toggleSaved(clipAt: index, in: model.list)
	}
}

@Observable
final class PickerModel {
	@ObservationIgnored var geometry = PickerGeometry()
	var draggedID: Clip.ID?
	var insertionID: Clip.ID?
	var insertionAtEnd = false
	/// A new model is made each time the picker opens, so it always opens on the history.
	private(set) var list = ClipList.history
	private(set) var state: PickerState
	/// The state of the list not shown and its clips at the time, so switching back keeps the selection.
	@ObservationIgnored private var otherState: (state: PickerState, clipIDs: [Clip.ID])?
	@ObservationIgnored private unowned let controller: AppController

	init(controller: AppController) {
		self.controller = controller
		state = PickerState(clips: controller.history.clips, initialSelection: controller.history.initialSelection)
	}

	var clips: [Clip] {
		controller.clips(in: list)
	}

	var images: ImageCache {
		controller.images(for: list)
	}

	var query: String {
		get { state.query }
		set { state.setQuery(newValue, clips: clips, stickySelection: controller.initialSelection(in: list)) }
	}

	/// Switches to another list, keeping the filter. If neither the filter nor that list changed since it was
	/// last shown, its selection is kept too.
	func show(_ newList: ClipList) {
		guard draggedID == nil, newList != list else { return }
		let query = state.query
		let previous = otherState
		otherState = (state: state, clipIDs: clips.map(\.id))
		list = newList
		if let previous, previous.state.query == query, previous.clipIDs == clips.map(\.id) {
			state = previous.state
		} else {
			state = PickerState(clips: clips, initialSelection: controller.initialSelection(in: list))
			state.setQuery(query, clips: clips, stickySelection: controller.initialSelection(in: list))
		}
	}

	func isSaved(_ clip: Clip) -> Bool {
		controller.isSaved(clip)
	}

	func moveSelection(by delta: Int) {
		state.moveSelection(by: delta)
	}

	func select(row: Int) {
		state.select(row: row)
	}

	func paste(row: Int) {
		state.select(row: row)
		guard let index = state.selectedClipIndex else { return }
		controller.paste(clipAt: index, in: list, plainText: false)
	}

	func toggleSaved(row: Int) {
		guard state.visibleIndices.indices.contains(row) else { return }
		controller.toggleSaved(clipAt: state.visibleIndices[row], in: list)
	}

	func move(_ id: Clip.ID, before destination: Clip.ID?) {
		controller.move(id, before: destination, in: list)
		if let index = clips.firstIndex(where: { $0.id == id }),
		   let row = state.visibleIndices.firstIndex(of: index) { state.select(row: row) }
	}

	func delete(_ id: Clip.ID) {
		controller.delete(id, in: list)
	}

	func reload() {
		state.reload(clips: clips)
	}
}
