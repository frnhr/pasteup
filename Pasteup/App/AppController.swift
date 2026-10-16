import AppKit
import KeyboardShortcuts
import Observation
import PasteupCore
import os

extension KeyboardShortcuts.Name {
	static let showPicker = Self("showPicker", initial: .init(.v, modifiers: [.control, .command]))
}

private let logger = Logger(subsystem: "com.franhrzenjak.pasteup", category: "controller")

/// Wires the clipboard monitor, the history, the store, and the picker together.
@Observable
final class AppController {
	private enum DefaultsKey {
		static let capacity = "historyCapacity"
	}

	static let capacityRange = 1...1000

	private(set) var history = ClipHistory()
	private(set) var capacity: Int

	@ObservationIgnored let images: ImageCache
	@ObservationIgnored private let store: ClipStore
	@ObservationIgnored private let monitor = ClipboardMonitor()
	@ObservationIgnored private lazy var picker = PickerController(controller: self)

	init() {
		let storedCapacity = UserDefaults.standard.object(forKey: DefaultsKey.capacity) as? Int
		capacity = storedCapacity ?? ClipHistory.defaultCapacity
		store = ClipStore(directory: ClipStore.defaultDirectory)
		images = ImageCache(store: store)
	}

	func start() {
		do {
			try store.prepare()
		} catch {
			Alerts.showError("Pasteup can't create its storage folder and will quit.", error: error)
			NSApp.terminate(nil)
			return
		}
		guard loadHistory() else { return }

		if !Paster.isTrusted {
			Paster.requestTrust()
		}

		if let captured = PasteboardCodec.capture(from: .general, date: .now) {
			ingest(captured, atLaunch: true)
		}
		monitor.onChange = { [weak self] in
			guard let self, let captured = PasteboardCodec.capture(from: .general, date: .now) else { return }
			ingest(captured, atLaunch: false)
		}
		monitor.start()

		KeyboardShortcuts.onKeyDown(for: .showPicker) { [weak self] in
			self?.togglePicker()
		}
	}

	// MARK: - Picker

	func showPicker() {
		picker.show()
	}

	func togglePicker() {
		if picker.isVisible {
			picker.close()
		} else {
			picker.show()
		}
	}

	/// Pastes the clip at `index` (full-list index) into the frontmost app.
	/// `plainText` drops all formatting and pastes only the text.
	func paste(clipAt index: Int, plainText: Bool) {
		let clip = history.clips[index]
		let items: [RawItem]
		do {
			if plainText {
				guard let text = try PasteboardCodec.plainText(of: clip, store: store) else {
					NSSound.beep()
					return
				}
				items = [[RawRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]]
			} else {
				items = try store.readItems(of: clip)
			}
		} catch {
			picker.close()
			Alerts.showError("Couldn't read the clip from disk.", error: error)
			return
		}

		picker.close()
		Paster.write(items, to: .general)
		monitor.acknowledgeOwnWrite()
		history.paste(at: index)
		save()

		guard Paster.isTrusted else {
			Alerts.showAccessibilityNeeded()
			return
		}
		Task {
			// Give the target app's window a moment to become key again after the panel closes.
			try? await Task.sleep(for: .milliseconds(50))
			Paster.postCommandV()
		}
	}

	func delete(clipAt index: Int) {
		let clip = history.delete(at: index)
		removeBlobs(of: [clip])
		save()
	}

	// MARK: - Settings and menu

	func setCapacity(_ newValue: Int) {
		let clamped = min(max(newValue, Self.capacityRange.lowerBound), Self.capacityRange.upperBound)
		guard clamped != capacity else { return }
		capacity = clamped
		UserDefaults.standard.set(clamped, forKey: DefaultsKey.capacity)
		let evicted = history.setCapacity(clamped)
		removeBlobs(of: evicted)
		save()
	}

	func confirmClearHistory() {
		let confirmed = Alerts.confirm(
			title: "Clear the clip history?",
			message: "All \(history.clips.count) clips will be deleted. This can't be undone.",
			confirmTitle: "Clear History"
		)
		guard confirmed else { return }
		let removed = history.removeAll()
		removeBlobs(of: removed)
		save()
	}

	// MARK: - Private

	private func ingest(_ captured: CapturedClip, atLaunch: Bool) {
		let clip = captured.clip
		// Blobs are written before the clip enters the history, so the index never points at missing files.
		do {
			try store.writeBlobs(of: clip, items: captured.items, thumbnail: captured.thumbnailPNG)
		} catch {
			store.removeBlobs(ofClipIDs: [clip.id])
			Alerts.showError("Couldn't save the copied item.", error: error)
			return
		}

		let result = atLaunch ? history.captureAtLaunch(clip) : history.capture(clip)
		switch result {
		case .skippedDuplicate:
			logger.debug("Skipped duplicate copy")
			store.removeBlobs(ofClipIDs: [clip.id])
		case .inserted(let evicted):
			removeBlobs(of: evicted)
			save()
		}
		picker.historyDidChange()
	}

	/// Returns false if the app is quitting because the history couldn't be loaded or set aside.
	private func loadHistory() -> Bool {
		do {
			if let index = try store.loadIndex() {
				history = ClipHistory(clips: index.clips, stickyRow: index.stickyRow)
			}
		} catch {
			do {
				let folder = try store.quarantineHistory()
				Alerts.showError(
					"The clip history couldn't be read. It was moved to \(folder.path) and Pasteup starts with an empty history.",
					error: error
				)
			} catch let moveError {
				Alerts.showError(
					"The clip history couldn't be read (\(error)), and moving it aside failed too. Pasteup will quit so it doesn't overwrite it.",
					error: moveError
				)
				NSApp.terminate(nil)
				return false
			}
		}
		removeBlobs(of: history.setCapacity(capacity))
		store.removeOrphanBlobs(keeping: Set(history.clips.map(\.id)))
		return true
	}

	private func removeBlobs(of clips: [Clip]) {
		guard !clips.isEmpty else { return }
		store.removeBlobs(ofClipIDs: clips.map(\.id))
		images.forget(clipIDs: clips.map(\.id))
	}

	private func save() {
		do {
			try store.saveIndex(HistoryIndex(history: history))
		} catch {
			Alerts.showError("Couldn't save the clip history.", error: error)
		}
	}
}
