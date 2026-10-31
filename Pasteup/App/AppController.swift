import AppKit
import KeyboardShortcuts
import Observation
import PasteupCore
import os

extension KeyboardShortcuts.Name {
	static let showPicker = Self("showPicker", initial: .init(.v, modifiers: [.control, .command]))
}

private let logger = Logger(subsystem: "com.franhrzenjak.pasteup", category: "controller")

/// The two clip lists, shown as tabs in the picker.
enum ClipList {
	case history
	case saved
}

/// Wires the clipboard monitor, the clip lists, their stores, and the picker together.
@Observable
final class AppController {
	private enum DefaultsKey {
		static let capacity = "historyCapacity"
	}

	static let capacityRange = 1...1000

	private(set) var history = ClipHistory()
	private(set) var saved = SavedClips()
	private(set) var capacity: Int

	@ObservationIgnored private let historyStore: ClipStore
	@ObservationIgnored private let savedStore: ClipStore
	@ObservationIgnored private let historyImages: ImageCache
	@ObservationIgnored private let savedImages: ImageCache
	@ObservationIgnored private let monitor = ClipboardMonitor()
	@ObservationIgnored private lazy var picker = PickerController(controller: self)

	init() {
		let storedCapacity = UserDefaults.standard.object(forKey: DefaultsKey.capacity) as? Int
		capacity = storedCapacity ?? ClipHistory.defaultCapacity
		historyStore = ClipStore(directory: ClipStore.historyDirectory, indexName: "history.json")
		savedStore = ClipStore(directory: ClipStore.savedDirectory, indexName: "saved.json")
		historyImages = ImageCache(store: historyStore)
		savedImages = ImageCache(store: savedStore)
	}

	func start() {
		do {
			try historyStore.prepare()
			try savedStore.prepare()
		} catch {
			Alerts.showError("Pasteup can't create its storage folder and will quit.", error: error)
			NSApp.terminate(nil)
			return
		}
		guard loadHistory(), loadSaved() else { return }

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

	func clips(in list: ClipList) -> [Clip] {
		switch list {
		case .history: history.clips
		case .saved: saved.clips
		}
	}

	/// The row to highlight when the list is shown.
	func initialSelection(in list: ClipList) -> Int? {
		switch list {
		case .history: history.initialSelection
		case .saved: saved.initialSelection
		}
	}

	func images(for list: ClipList) -> ImageCache {
		switch list {
		case .history: historyImages
		case .saved: savedImages
		}
	}

	/// Whether a clip with the same content is in the saved list.
	func isSaved(_ clip: Clip) -> Bool {
		saved.contains(contentHash: clip.contentHash)
	}

	/// Pastes the clip at `index` (full-list index) into the frontmost app.
	/// `plainText` drops all formatting and pastes only the text.
	func paste(clipAt index: Int, in list: ClipList, plainText: Bool) {
		let clip = clips(in: list)[index]
		let store = store(for: list)
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
		switch list {
		case .history: history.paste(at: index)
		case .saved: saved.paste(at: index)
		}
		writeIndex(of: list)

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

	/// In the saved list, this is the same as unsaving.
	func delete(clipAt index: Int, in list: ClipList) {
		let clip = switch list {
		case .history: history.delete(at: index)
		case .saved: saved.delete(at: index)
		}
		removeBlobs(of: [clip], from: list)
		writeIndex(of: list)
		picker.listsDidChange()
	}

	/// Saves a copy of the clip at `index`, or unsaves it if a clip with the same content is already saved.
	func toggleSaved(clipAt index: Int, in list: ClipList) {
		let clip = clips(in: list)[index]
		if let unsaved = saved.delete(contentHash: clip.contentHash) {
			removeBlobs(of: [unsaved], from: .saved)
		} else {
			// A copy with its own ID and blobs, so deleting or evicting the history clip doesn't affect it.
			var copy = clip
			copy.id = UUID()
			do {
				try store(for: list).copyBlobs(of: clip, to: savedStore, as: copy.id)
			} catch {
				savedStore.removeBlobs(ofClipIDs: [copy.id])
				Alerts.showError("Couldn't save the clip.", error: error)
				return
			}
			let inserted = saved.save(copy)
			assert(inserted, "the clip was checked to be unsaved above")
		}
		writeIndex(of: .saved)
		picker.listsDidChange()
	}

	// MARK: - Settings and menu

	func setCapacity(_ newValue: Int) {
		let clamped = min(max(newValue, Self.capacityRange.lowerBound), Self.capacityRange.upperBound)
		guard clamped != capacity else { return }
		capacity = clamped
		UserDefaults.standard.set(clamped, forKey: DefaultsKey.capacity)
		let evicted = history.setCapacity(clamped)
		removeBlobs(of: evicted, from: .history)
		writeIndex(of: .history)
		picker.listsDidChange()
	}

	func confirmClearHistory() {
		let confirmed = Alerts.confirm(
			title: "Clear the clip history?",
			message: "All \(history.clips.count) clips will be deleted. Saved clips are kept. This can't be undone.",
			confirmTitle: "Clear History"
		)
		guard confirmed else { return }
		let removed = history.removeAll()
		removeBlobs(of: removed, from: .history)
		writeIndex(of: .history)
		picker.listsDidChange()
	}

	// MARK: - Private

	private func ingest(_ captured: CapturedClip, atLaunch: Bool) {
		let clip = captured.clip
		// Blobs are written before the clip enters the history, so the index never points at missing files.
		do {
			try historyStore.writeBlobs(of: clip, items: captured.items, thumbnail: captured.thumbnailPNG)
		} catch {
			historyStore.removeBlobs(ofClipIDs: [clip.id])
			Alerts.showError("Couldn't save the copied item.", error: error)
			return
		}

		let result = atLaunch ? history.captureAtLaunch(clip) : history.capture(clip)
		switch result {
		case .skippedDuplicate:
			logger.debug("Skipped duplicate copy")
			historyStore.removeBlobs(ofClipIDs: [clip.id])
		case .inserted(let evicted):
			removeBlobs(of: evicted, from: .history)
			writeIndex(of: .history)
		}
		picker.listsDidChange()
	}

	/// Returns false if the app is quitting because the history couldn't be loaded or set aside.
	private func loadHistory() -> Bool {
		let loaded = loadIndex(of: historyStore, name: "clip history") { index in
			history = ClipHistory(clips: index.clips, stickyRow: index.stickyRow)
		}
		guard loaded else { return false }
		removeBlobs(of: history.setCapacity(capacity), from: .history)
		historyStore.removeOrphanBlobs(keeping: Set(history.clips.map(\.id)))
		return true
	}

	/// Returns false if the app is quitting because the saved clips couldn't be loaded or set aside.
	private func loadSaved() -> Bool {
		let loaded = loadIndex(of: savedStore, name: "list of saved clips") { index in
			saved = SavedClips(clips: index.clips, stickyRow: index.stickyRow)
		}
		guard loaded else { return false }
		savedStore.removeOrphanBlobs(keeping: Set(saved.clips.map(\.id)))
		return true
	}

	/// Passes the stored index, if there is one, to `apply`. An unreadable index is moved aside and the list
	/// starts empty. Returns false if the app is quitting because moving it aside failed too.
	private func loadIndex(of store: ClipStore, name: String, apply: (ClipIndex) -> Void) -> Bool {
		do {
			if let index = try store.loadIndex() {
				apply(index)
			}
		} catch {
			do {
				let folder = try store.quarantineIndex()
				Alerts.showError(
					"The \(name) couldn't be read. It was moved to \(folder.path) and Pasteup starts with an empty list.",
					error: error
				)
			} catch let moveError {
				Alerts.showError(
					"The \(name) couldn't be read (\(error)), and moving it aside failed too. Pasteup will quit so it doesn't overwrite it.",
					error: moveError
				)
				NSApp.terminate(nil)
				return false
			}
		}
		return true
	}

	private func store(for list: ClipList) -> ClipStore {
		switch list {
		case .history: historyStore
		case .saved: savedStore
		}
	}

	private func removeBlobs(of clips: [Clip], from list: ClipList) {
		guard !clips.isEmpty else { return }
		store(for: list).removeBlobs(ofClipIDs: clips.map(\.id))
		images(for: list).forget(clipIDs: clips.map(\.id))
	}

	private func writeIndex(of list: ClipList) {
		do {
			switch list {
			case .history: try historyStore.saveIndex(ClipIndex(history: history))
			case .saved: try savedStore.saveIndex(ClipIndex(saved: saved))
			}
		} catch {
			Alerts.showError(list == .history ? "Couldn't save the clip history." : "Couldn't store the saved clips.", error: error)
		}
	}
}
