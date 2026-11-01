import Foundation
import Testing
@testable import PasteupCore

@Suite("Clip arrangement")
struct ArrangementTests {
	@Test("Both lists support upward, downward and end moves and preserve paste semantics")
	func moves() {
		let clips = [textClip("A"), textClip("B"), textClip("C"), textClip("D")]
		var history = ClipHistory(clips: clips)
		var saved = SavedClips(clips: clips)
		for (source, destination, expected) in [
			(3, Optional(1), [0, 3, 1, 2]),
			(0, Optional(2), [3, 1, 0, 2]),
			(1, nil, [3, 0, 2, 1]),
			(2, Optional(3), [2, 3, 0, 1])
		] {
			let movedHistory = history.move(clips[source].id, before: destination.map { clips[$0].id })
			#expect(movedHistory)
			let movedSaved = saved.move(clips[source].id, before: destination.map { clips[$0].id })
			#expect(movedSaved)
			#expect(history.clips.map(\.id) == expected.map { clips[$0].id })
			#expect(saved.clips.map(\.id) == expected.map { clips[$0].id })
			#expect(history.initialSelection == expected.firstIndex(of: source))
			#expect(saved.initialSelection == history.initialSelection)
		}
		let pastedHistory = history.paste(at: 2)
		#expect(pastedHistory.id == clips[0].id)
		let pastedSaved = saved.paste(at: 2)
		#expect(pastedSaved.id == clips[0].id)
		#expect(history.stickyRow == 2)
		#expect(saved.stickyRow == 2)
		#expect(saved.contains(contentHash: clips[0].contentHash))
	}

	@Test("Moves resolve IDs after new arrivals, and missing IDs never move a different clip")
	func arrivalsAndEviction() {
		let clips = [textClip("A"), textClip("B"), textClip("C")]
		var history = ClipHistory(clips: clips)
		var saved = SavedClips(clips: clips)
		let new = textClip("new", at: 10)
		_ = history.capture(new)
		_ = saved.save(new)
		let movedHistory = history.move(clips[2].id, before: clips[0].id)
		#expect(movedHistory)
		let movedSaved = saved.move(clips[2].id, before: clips[0].id)
		#expect(movedSaved)
		#expect(history.clips.map(\.id) == [new.id, clips[2].id, clips[0].id, clips[1].id])
		#expect(saved.clips == history.clips)
		let before = history.clips
		for (id, target) in [(UUID(), Optional(clips[0].id)), (clips[0].id, Optional(UUID())), (clips[0].id, Optional(clips[0].id))] {
			let movedHistory = history.move(id, before: target)
			#expect(!movedHistory)
			let movedSaved = saved.move(id, before: target)
			#expect(!movedSaved)
			#expect(history.clips == before)
			#expect(saved.clips == before)
		}
	}

	@Test("Reordered indices round-trip with their remembered row in both lists")
	func persistence() throws {
		let clips = (0..<1000).map { textClip("clip \($0)") }
		var history = ClipHistory(clips: clips)
		var saved = SavedClips(clips: clips)
		_ = history.move(clips[0].id, before: nil)
		_ = saved.move(clips[0].id, before: nil)
		let historyIndex = try ClipIndex.decode(ClipIndex(history: history).encoded())
		let savedIndex = try ClipIndex.decode(ClipIndex(saved: saved).encoded())
		let reopened = ClipHistory(clips: historyIndex.clips, stickyRow: historyIndex.stickyRow)
		let reopenedSaved = SavedClips(clips: savedIndex.clips, stickyRow: savedIndex.stickyRow)
		#expect(reopened.clips == history.clips)
		#expect(reopenedSaved.clips == saved.clips)
		#expect(reopened.initialSelection == 999)
		#expect(reopenedSaved.initialSelection == 999)
	}
}
