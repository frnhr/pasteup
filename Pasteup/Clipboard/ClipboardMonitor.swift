import AppKit

/// Detects clipboard changes. macOS has no change notification, so this polls `changeCount`.
final class ClipboardMonitor {
	static let pollInterval: TimeInterval = 0.3

	var onChange: (() -> Void)?

	private let pasteboard = NSPasteboard.general
	private var lastChangeCount: Int
	private var timer: Timer?

	init() {
		lastChangeCount = pasteboard.changeCount
	}

	func start() {
		let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.poll()
			}
		}
		timer.tolerance = 0.1
		self.timer = timer
	}

	/// Call right after the app wrote to the clipboard itself, so that write isn't treated as a copy.
	func acknowledgeOwnWrite() {
		lastChangeCount = pasteboard.changeCount
	}

	private func poll() {
		let changeCount = pasteboard.changeCount
		guard changeCount != lastChangeCount else { return }
		lastChangeCount = changeCount
		onChange?()
	}
}
