import Foundation
import Testing
@testable import PasteupCore

@Suite("Sticky row")
struct StickyRowTests {
	@Test("Repeated paste from the same row pastes the history in original copy order")
	func serialPaste() throws {
		var history = ClipHistory.copied(["A", "B", "C", "D"])
		#expect(history.texts == ["D", "C", "B", "A"])
		#expect(history.initialSelection == 0)

		// First round: the user moves down to A (row 3) and pastes.
		var pasted = [history.paste(at: 3).preview.text]
		// Every following round: the picker opens on the sticky row, user just presses Enter.
		for _ in 0..<3 {
			let row = try #require(history.initialSelection)
			#expect(row == 3)
			pasted.append(history.paste(at: row).preview.text)
		}

		#expect(pasted == ["A", "B", "C", "D"])
		#expect(history.texts == ["D", "C", "B", "A"])
	}

	@Test("Pasting moves the clip to the top and remembers its row")
	func pasteMovesToTop() {
		var history = ClipHistory.copied(["A", "B", "C", "D"])
		history.paste(at: 2)
		#expect(history.texts == ["B", "D", "C", "A"])
		#expect(history.stickyRow == 2)
		#expect(history.initialSelection == 2)
	}

	@Test("A new copy resets the sticky row to the top")
	func newCopyResets() {
		var history = ClipHistory.copied(["A", "B", "C"])
		history.paste(at: 2)
		_ = history.capture(textClip("E", at: 100))
		#expect(history.initialSelection == 0)
		#expect(history.texts.first == "E")
	}

	@Test("Empty history has no selection")
	func emptyHistory() {
		#expect(ClipHistory().initialSelection == nil)
	}

	@Test("Deleting clamps the sticky row to the shorter list")
	func deleteClamps() {
		var history = ClipHistory.copied(["A", "B", "C", "D"])
		history.paste(at: 3)
		history.delete(at: 0)
		#expect(history.clips.count == 3)
		#expect(history.stickyRow == 2)
		#expect(history.initialSelection == 2)
	}

	@Test("Deleting below the sticky row keeps it")
	func deleteBelowKeepsRow() {
		var history = ClipHistory.copied(["A", "B", "C", "D"])
		history.paste(at: 1)
		history.delete(at: 3)
		#expect(history.stickyRow == 1)
	}

	@Test("Restored sticky row is clamped to the restored clips")
	func restoredStickyRowClamped() {
		let history = ClipHistory(clips: [textClip("A"), textClip("B")], stickyRow: 7)
		#expect(history.stickyRow == 1)
	}
}

@Suite("Duplicate detection")
struct DuplicateTests {
	@Test("Identical copy within the window is skipped")
	func quickRepeatSkipped() {
		var history = ClipHistory()
		_ = history.capture(textClip("A", at: 0))
		#expect(history.capture(textClip("A", at: 1.5)) == .skippedDuplicate)
		#expect(history.texts == ["A"])
	}

	@Test("The window slides with each repeated copy")
	func windowSlides() {
		var history = ClipHistory()
		_ = history.capture(textClip("A", at: 0))
		#expect(history.capture(textClip("A", at: 1.5)) == .skippedDuplicate)
		#expect(history.capture(textClip("A", at: 3.0)) == .skippedDuplicate)
		#expect(history.texts == ["A"])
	}

	@Test("Identical copy after the window is kept as a duplicate entry")
	func slowRepeatKept() {
		var history = ClipHistory()
		_ = history.capture(textClip("A", at: 0))
		#expect(history.capture(textClip("A", at: 2.5)) == .inserted(evicted: []))
		#expect(history.texts == ["A", "A"])
	}

	@Test("Copying an older clip again inserts a duplicate entry, even quickly")
	func olderDuplicateKept() {
		var history = ClipHistory()
		_ = history.capture(textClip("A", at: 0))
		_ = history.capture(textClip("B", at: 0.5))
		_ = history.capture(textClip("A", at: 1.0))
		#expect(history.texts == ["A", "B", "A"])
	}

	@Test("A paste in between means the top clip differs, so the copy is kept")
	func pasteInBetween() {
		var history = ClipHistory()
		_ = history.capture(textClip("A", at: 0))
		_ = history.capture(textClip("B", at: 10))
		_ = history.capture(textClip("A", at: 11))
		history.paste(at: 1) // B to the top
		_ = history.capture(textClip("A", at: 12))
		#expect(history.texts == ["A", "B", "A", "A"])
	}

	@Test("At launch, content identical to the top clip is skipped regardless of time")
	func launchCaptureSkipsTop() {
		var history = ClipHistory.copied(["A", "B"])
		#expect(history.captureAtLaunch(textClip("B", at: 99_999)) == .skippedDuplicate)
		#expect(history.captureAtLaunch(textClip("A", at: 99_999)) == .inserted(evicted: []))
		#expect(history.texts == ["A", "B", "A"])
	}

	@Test("Launch capture of new content resets the sticky row")
	func launchCaptureResetsSticky() {
		var history = ClipHistory.copied(["A", "B", "C"])
		history.paste(at: 2)
		_ = history.captureAtLaunch(textClip("Z", at: 1_000))
		#expect(history.initialSelection == 0)
	}
}

@Suite("Capacity")
struct CapacityTests {
	@Test("Capturing beyond capacity evicts the oldest clips")
	func evictsOldest() {
		var history = ClipHistory()
		_ = history.setCapacity(3)
		for (offset, text) in ["A", "B", "C"].enumerated() {
			_ = history.capture(textClip(text, at: TimeInterval(offset * 10)))
		}
		let result = history.capture(textClip("D", at: 100))
		guard case .inserted(let evicted) = result else {
			Issue.record("expected insertion, got \(result)")
			return
		}
		#expect(evicted.map(\.preview.text) == ["A"])
		#expect(history.texts == ["D", "C", "B"])
	}

	@Test("Lowering capacity evicts and clamps the sticky row")
	func lowerCapacity() {
		var history = ClipHistory.copied(["A", "B", "C", "D", "E"])
		history.paste(at: 4)
		#expect(history.stickyRow == 4)
		let evicted = history.setCapacity(2)
		#expect(evicted.map(\.preview.text) == ["D", "C", "B"])
		#expect(history.texts == ["A", "E"])
		#expect(history.stickyRow == 1)
	}

	@Test("Remove all empties the history and resets the sticky row")
	func removeAll() {
		var history = ClipHistory.copied(["A", "B", "C"])
		history.paste(at: 2)
		#expect(history.removeAll().count == 3)
		#expect(history.clips.isEmpty)
		#expect(history.stickyRow == 0)
	}
}
