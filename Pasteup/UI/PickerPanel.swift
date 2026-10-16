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
		let hostingView = NSHostingView(rootView: PickerView(model: model, images: controller.images))
		// Without this, the hidden title bar's height is reserved as a safe area and added to the panel's height.
		hostingView.safeAreaRegions = []
		panel.contentView = hostingView
		center(panel)
		panel.makeKeyAndOrderFront(nil)
	}

	func close() {
		guard let panel, panel.isVisible else { return }
		panel.orderOut(nil)
		panel.contentView = nil
		model = nil
	}

	/// Keeps an open picker in sync when a copy or delete changes the history.
	func historyDidChange() {
		model?.reload()
	}

	private func makePanel() -> PickerPanel {
		let panel = PickerPanel()
		panel.keyDownHandler = { [weak self] event in
			self?.handleKeyDown(event) ?? false
		}
		panel.onResignKey = { [weak self] in
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
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		switch Int(event.keyCode) {
		case kVK_UpArrow:
			model.moveSelection(by: -1)
		case kVK_DownArrow:
			model.moveSelection(by: 1)
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
		guard let index = model?.state.selectedClipIndex else {
			NSSound.beep()
			return
		}
		controller.paste(clipAt: index, plainText: plainText)
	}

	private func deleteSelection() {
		guard let index = model?.state.selectedClipIndex else {
			NSSound.beep()
			return
		}
		controller.delete(clipAt: index)
		model?.reload()
	}
}

@Observable
final class PickerModel {
	private(set) var state: PickerState
	@ObservationIgnored private unowned let controller: AppController

	init(controller: AppController) {
		self.controller = controller
		state = PickerState(clips: controller.history.clips, initialSelection: controller.history.initialSelection)
	}

	var clips: [Clip] {
		controller.history.clips
	}

	var query: String {
		get { state.query }
		set { state.setQuery(newValue, clips: clips, stickySelection: controller.history.initialSelection) }
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
		controller.paste(clipAt: index, plainText: false)
	}

	func reload() {
		state.reload(clips: clips)
	}
}
