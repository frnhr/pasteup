import AppKit
import Carbon.HIToolbox
import PasteupCore
import SwiftUI

/// SwiftUI applies row placement and scrolling in its render tree. Native representable
/// frames need not include those transforms, so resolve targets from SwiftUI geometry.
struct PickerGeometry: Equatable {
	var rows: [Clip.ID: CGRect] = [:]
	var viewport: CGRect = .zero
}

struct PickerGeometryKey: PreferenceKey {
	static let defaultValue = PickerGeometry()
	static func reduce(value: inout PickerGeometry, nextValue: () -> PickerGeometry) {
		let next = nextValue()
		value.rows.merge(next.rows) { _, new in new }
		if !next.viewport.isEmpty { value.viewport = next.viewport }
	}
}

/// An internal mouse gesture, not an AppKit export drag. Only an actual mouse-up commits;
/// Escape, window teardown and a lost mouse-up cancel. No pasteboard content is exported.
final class PickerArrangement {
	private weak var panel: PickerPanel?
	private let model: PickerModel
	private let pointerLocation: () -> NSPoint
	private var candidate: (id: Clip.ID, point: NSPoint)?
	private var timer: Timer?
	private var feedback: NSPanel?
	private var target: Clip.ID?
	private var hasTarget = false
	private var outside = false
	var isTracking: Bool { candidate != nil }

	init(panel: PickerPanel, model: PickerModel, pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
		self.panel = panel
		self.model = model
		self.pointerLocation = pointerLocation
	}

	private var scrollView: NSScrollView? {
		func find(_ view: NSView) -> NSScrollView? {
			if let scroll = view as? NSScrollView { return scroll }
			return view.subviews.lazy.compactMap { find($0) }.first
		}
		return panel?.contentView.flatMap { find($0) }
	}

	/// The named SwiftUI picker space starts at the hosting view's top-left corner.
	private func pickerPoint(_ screenPoint: NSPoint) -> CGPoint {
		guard let panel, let view = panel.contentView else { return .zero }
		let point = view.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
		return CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
	}

	func handle(_ event: NSEvent) -> Bool {
		if event.type == .keyDown, isTracking {
			if Int(event.keyCode) == kVK_Escape { cancel() }
			return true
		}
		if event.type == .leftMouseDown {
			let point = pointerLocation()
			let local = pickerPoint(point)
			if event.clickCount == 1, model.geometry.viewport.contains(local),
			   let row = model.geometry.rows.first(where: {
				let rect = $0.value
				// Leave the bookmark control available for its normal click action.
				return rect.width > 40 && CGRect(x: rect.minX, y: rect.minY, width: rect.width - 40, height: rect.height).contains(local)
			}) {
				candidate = (row.key, point)
			}
			return false
		}
		guard let candidate else { return false }
		if event.type == .leftMouseDragged {
			if model.draggedID == nil {
				let point = pointerLocation()
				guard hypot(point.x - candidate.point.x, point.y - candidate.point.y) >= 5 else { return false }
				model.draggedID = candidate.id
				let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
					MainActor.assumeIsolated { self?.tick() }
				}
				self.timer = timer
				RunLoop.main.add(timer, forMode: .common)
			}
			update()
			return true
		}
		if event.type == .leftMouseUp {
			guard model.draggedID != nil else { cancel(); return false }
			update()
			let delete = outside
			let destination = target
			let move = hasTarget && !model.state.isFiltering
			cancel()
			if delete { model.delete(candidate.id) }
			else if move { model.move(candidate.id, before: destination) }
			return true
		}
		return false
	}

	private func tick() {
		guard NSEvent.pressedMouseButtons & 1 != 0 else { cancel(); return }
		guard let panel else { cancel(); return }
		let point = pointerLocation()
		if panel.frame.contains(point), let scroll = scrollView {
			let viewport = model.geometry.viewport
			let local = pickerPoint(point)
			if viewport.contains(local), let document = scroll.documentView {
				let direction: CGFloat = local.y < viewport.minY + 28 ? -1 : (local.y > viewport.maxY - 28 ? 1 : 0)
				if direction != 0 {
					let clip = scroll.contentView
					let delta = direction * 10 * (document.isFlipped ? 1 : -1)
					let y = min(max(clip.bounds.minY + delta, document.bounds.minY), max(document.bounds.minY, document.bounds.maxY - clip.bounds.height))
					clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
					scroll.reflectScrolledClipView(clip)
				}
			}
		}
		update()
	}

	private func update() {
		guard let panel, let candidate, model.draggedID != nil else { return }
		guard model.clips.contains(where: { $0.id == candidate.id }) else { cancel(); return }
		let point = pointerLocation()
		outside = !panel.frame.contains(point)
		hasTarget = false
		target = nil
		model.insertionID = nil
		model.insertionAtEnd = false
		let local = pickerPoint(point)
		let rows = model.geometry.rows.filter { $0.key != candidate.id && $0.value.intersects(model.geometry.viewport) }
			.sorted { $0.value.midY < $1.value.midY }
		if !outside, !model.state.isFiltering,
		   model.geometry.viewport.contains(local), !rows.isEmpty {
			hasTarget = true
			if let next = rows.first(where: { local.y < $0.value.midY }) {
				target = next.key
			} else if let last = rows.last,
			          let index = model.clips.firstIndex(where: { $0.id == last.key }) {
				target = model.clips.dropFirst(index + 1).first(where: { $0.id != candidate.id })?.id
			}
			model.insertionID = target
			model.insertionAtEnd = target == nil
		}
		showFeedback(at: point)
	}

	private func showFeedback(at point: NSPoint) {
		let badge = feedback ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		if feedback == nil {
			badge.isReleasedWhenClosed = false
			badge.level = .statusBar
			badge.ignoresMouseEvents = true
			badge.isOpaque = false
			badge.backgroundColor = .clear
			badge.hasShadow = true
			badge.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
			feedback = badge
		}
		let label = outside ? "Release to delete" : (model.state.isFiltering ? "Clear filter to reorder · Drag outside to delete" : "Drag to arrange · Esc to cancel")
		badge.contentView = NSHostingView(rootView:
			Label(label, systemImage: outside ? "trash.fill" : "arrow.up.arrow.down")
				.font(.system(size: 13, weight: .semibold))
				.padding(10).foregroundStyle(outside ? Color.white : Color.primary)
				.background(outside ? Color.red : Color(nsColor: .windowBackgroundColor))
				.clipShape(RoundedRectangle(cornerRadius: 8)))
		let size = badge.contentView!.fittingSize
		// AppKit screen coordinates work on displays left of or above the primary display too.
		let screen = NSScreen.screens.first { $0.frame.contains(point) }?.frame ?? panel?.frame ?? .zero
		let origin = NSPoint(x: min(max(point.x + 16, screen.minX), screen.maxX - size.width),
		                     y: min(max(point.y - size.height - 16, screen.minY), screen.maxY - size.height))
		badge.setFrame(NSRect(origin: origin, size: size), display: true)
		badge.orderFrontRegardless()
	}

	func cancel() {
		timer?.invalidate()
		timer = nil
		feedback?.orderOut(nil)
		feedback = nil
		candidate = nil
		model.draggedID = nil
		model.insertionID = nil
		model.insertionAtEnd = false
	}
}
