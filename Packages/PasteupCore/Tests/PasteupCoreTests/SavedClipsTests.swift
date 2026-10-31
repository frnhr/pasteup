import Foundation
import Testing
@testable import PasteupCore

extension SavedClips {
	/// Previews (texts) of all saved clips, top first.
	var texts: [String] {
		clips.map { $0.preview.text ?? "?" }
	}

	/// Saves each text in order, so the last one ends up on top.
	static func saved(_ texts: [String]) -> SavedClips {
		var saved = SavedClips()
		for text in texts {
			_ = saved.save(textClip(text))
		}
		return saved
	}
}

@Suite("Saved clips")
struct SavedClipsTests {
	@Test("Saving adds the clip at the top")
	func saveAddsAtTop() {
		let saved = SavedClips.saved(["A", "B", "C"])
		#expect(saved.texts == ["C", "B", "A"])
		#expect(saved.contains(contentHash: "hash-B"))
		#expect(!saved.contains(contentHash: "hash-Z"))
	}

	@Test("Saving the same content again changes nothing")
	func saveDeduplicates() {
		var saved = SavedClips.saved(["A", "B"])
		saved.paste(at: 1)
		let inserted = saved.save(textClip("B", at: 500))
		#expect(!inserted)
		#expect(saved.texts == ["A", "B"])
		#expect(saved.stickyRow == 1)
	}

	@Test("Saving new content resets the sticky row")
	func saveResetsStickyRow() {
		var saved = SavedClips.saved(["A", "B", "C"])
		saved.paste(at: 2)
		let inserted = saved.save(textClip("D"))
		#expect(inserted)
		#expect(saved.initialSelection == 0)
	}

	@Test("Repeated paste from the same row pastes the list in saved order")
	func serialPaste() throws {
		var saved = SavedClips.saved(["A", "B", "C"])
		var pasted = [saved.paste(at: 2).preview.text]
		for _ in 0..<2 {
			let row = try #require(saved.initialSelection)
			pasted.append(saved.paste(at: row).preview.text)
		}
		#expect(pasted == ["A", "B", "C"])
	}

	@Test("Deleting by content hash removes the clip and allows saving it again")
	func deleteByContentHash() {
		var saved = SavedClips.saved(["A", "B", "C"])
		let deleted = saved.delete(contentHash: "hash-B")
		#expect(deleted?.preview.text == "B")
		#expect(saved.texts == ["C", "A"])
		#expect(!saved.contains(contentHash: "hash-B"))
		let deletedAgain = saved.delete(contentHash: "hash-B")
		#expect(deletedAgain == nil)
		let savedAgain = saved.save(textClip("B"))
		#expect(savedAgain)
		#expect(saved.texts == ["B", "C", "A"])
	}

	@Test("Deleting by row clamps the sticky row")
	func deleteClamps() {
		var saved = SavedClips.saved(["A", "B", "C"])
		saved.paste(at: 2)
		saved.delete(at: 0)
		#expect(saved.stickyRow == 1)
		#expect(!saved.contains(contentHash: "hash-A"))
	}

	@Test("Restoring drops duplicate content and clamps the sticky row")
	func restoreDeduplicates() {
		let saved = SavedClips(clips: [textClip("A"), textClip("B"), textClip("A")], stickyRow: 9)
		#expect(saved.texts == ["A", "B"])
		#expect(saved.stickyRow == 1)
	}

	@Test("Round-trips through the index format")
	func roundTrip() throws {
		var saved = SavedClips.saved(["A", "B", "C"])
		saved.paste(at: 2)
		let decoded = try ClipIndex.decode(ClipIndex(saved: saved).encoded())
		let restored = SavedClips(clips: decoded.clips, stickyRow: decoded.stickyRow)
		#expect(restored.clips == saved.clips)
		#expect(restored.stickyRow == 2)
	}
}
