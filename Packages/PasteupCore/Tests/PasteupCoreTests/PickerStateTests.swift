import Foundation
import Testing
@testable import PasteupCore

@Suite("Picker state")
struct PickerStateTests {
	let clips = ["Ćevapi recipe", "meeting notes", "CEVAPCICI", "grocery list"].map { textClip($0) }

	@Test("Opens on the given initial selection with all rows visible")
	func opensOnInitialSelection() {
		let state = PickerState(clips: clips, initialSelection: 2)
		#expect(state.visibleIndices == [0, 1, 2, 3])
		#expect(state.selectedClipIndex == 2)
	}

	@Test("Filter is case- and diacritic-insensitive and selects the first match")
	func filterSelectsFirstMatch() {
		var state = PickerState(clips: clips, initialSelection: 3)
		state.setQuery("cevap", clips: clips, stickySelection: 3)
		#expect(state.visibleIndices == [0, 2])
		#expect(state.selection == 0)
		#expect(state.selectedClipIndex == 0)
	}

	@Test("Selection in a filtered list maps to the full-list index")
	func filteredSelectionMapsToFullIndex() {
		var state = PickerState(clips: clips, initialSelection: 0)
		state.setQuery("cevap", clips: clips, stickySelection: 0)
		state.moveSelection(by: 1)
		#expect(state.selectedClipIndex == 2)
	}

	@Test("Clearing the filter returns to the sticky selection")
	func clearingRestoresSticky() {
		var state = PickerState(clips: clips, initialSelection: 3)
		state.setQuery("notes", clips: clips, stickySelection: 3)
		#expect(state.selectedClipIndex == 1)
		state.setQuery("", clips: clips, stickySelection: 3)
		#expect(state.visibleIndices == [0, 1, 2, 3])
		#expect(state.selectedClipIndex == 3)
	}

	@Test("Whitespace-only query does not filter")
	func whitespaceQuery() {
		var state = PickerState(clips: clips, initialSelection: 1)
		state.setQuery("   ", clips: clips, stickySelection: 1)
		#expect(state.visibleIndices.count == 4)
		#expect(state.selectedClipIndex == 1)
	}

	@Test("No matches means no selection")
	func noMatches() {
		var state = PickerState(clips: clips, initialSelection: 0)
		state.setQuery("xyz", clips: clips, stickySelection: 0)
		#expect(state.visibleIndices.isEmpty)
		#expect(state.selectedClipIndex == nil)
		state.moveSelection(by: 1)
		#expect(state.selectedClipIndex == nil)
	}

	@Test("Moving the selection is clamped to the visible rows")
	func moveClamps() {
		var state = PickerState(clips: clips, initialSelection: 0)
		state.moveSelection(by: -1)
		#expect(state.selection == 0)
		state.moveSelection(by: 10)
		#expect(state.selection == 3)
	}

	@Test("Reload after deleting keeps the visual position, clamped")
	func reloadAfterDelete() {
		var history = ClipHistory(clips: clips)
		var state = PickerState(clips: history.clips, initialSelection: 3)
		history.delete(at: 3)
		state.reload(clips: history.clips)
		#expect(state.visibleIndices == [0, 1, 2])
		#expect(state.selection == 2)
	}

	@Test("Pasting from a filtered list sets the sticky row to the full-list index")
	func filteredPasteStickyRow() throws {
		var history = ClipHistory(clips: clips)
		var state = PickerState(clips: history.clips, initialSelection: history.initialSelection)
		state.setQuery("grocery", clips: history.clips, stickySelection: history.initialSelection)
		let index = try #require(state.selectedClipIndex)
		history.paste(at: index)
		#expect(history.stickyRow == 3)
	}
}

@Suite("Persistence format")
struct HistoryIndexTests {
	@Test("Round-trips through JSON")
	func roundTrip() throws {
		var history = ClipHistory.copied(["A", "B", "C"])
		history.paste(at: 2)
		let index = HistoryIndex(history: history)
		let decoded = try HistoryIndex.decode(index.encoded())
		#expect(decoded == index)
		#expect(decoded.stickyRow == 2)
	}

	@Test("Rejects an unknown version")
	func rejectsUnknownVersion() throws {
		var index = HistoryIndex(history: ClipHistory.copied(["A"]))
		index.version = 99
		let data = try index.encoded()
		#expect(throws: HistoryIndex.DecodingError.self) {
			try HistoryIndex.decode(data)
		}
	}
}

@Suite("Content hash and preview text")
struct HashAndPreviewTests {
	let text = RawRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8))
	let html = RawRepresentation(type: "public.html", data: Data("<b>hello</b>".utf8))

	@Test("Same content hashes the same")
	func sameContent() {
		#expect(ContentHash.of([[text, html]]) == ContentHash.of([[text, html]]))
	}

	@Test("Type, data, and item boundaries all affect the hash")
	func differences() {
		let base = ContentHash.of([[text, html]])
		let retyped = RawRepresentation(type: "public.rtf", data: html.data)
		#expect(ContentHash.of([[text, retyped]]) != base)
		#expect(ContentHash.of([[text]]) != base)
		#expect(ContentHash.of([[text], [html]]) != base)
	}

	@Test("Excerpt collapses whitespace and truncates")
	func excerpt() {
		#expect(PreviewText.excerpt(from: "  one\n\n two\tthree  ") == "one two three")
		let long = String(repeating: "x", count: 500)
		let excerpt = PreviewText.excerpt(from: long)
		#expect(excerpt.count == PreviewText.excerptLength + 1)
		#expect(excerpt.hasSuffix("…"))
	}
}
