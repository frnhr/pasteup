import Foundation

public enum HistoryFilter {
	/// Case- and diacritic-insensitive substring match ("cevap" matches "Ćevapi").
	public static func matches(_ clip: Clip, query: String) -> Bool {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		return trimmed.isEmpty || clip.searchText.localizedStandardContains(trimmed)
	}
}

/// Selection and filtering inside an open picker. Indices into `visibleIndices` are "rows";
/// the values are full-list indices into `ClipHistory.clips`.
public struct PickerState: Equatable, Sendable {
	public private(set) var query = ""
	public private(set) var visibleIndices: [Int]
	public private(set) var selection: Int?

	public init(clips: [Clip], initialSelection: Int?) {
		visibleIndices = Array(clips.indices)
		selection = initialSelection
	}

	public var selectedClipIndex: Int? {
		selection.map { visibleIndices[$0] }
	}

	public var isFiltering: Bool {
		!query.trimmingCharacters(in: .whitespaces).isEmpty
	}

	/// While filtering, the first match is selected; clearing the query returns to `stickySelection`.
	public mutating func setQuery(_ newQuery: String, clips: [Clip], stickySelection: Int?) {
		query = newQuery
		visibleIndices = clips.indices.filter { HistoryFilter.matches(clips[$0], query: newQuery) }
		if isFiltering {
			selection = visibleIndices.isEmpty ? nil : 0
		} else {
			selection = stickySelection
		}
	}

	public mutating func moveSelection(by delta: Int) {
		guard !visibleIndices.isEmpty else { return }
		let current = selection ?? 0
		selection = max(0, min(current + delta, visibleIndices.count - 1))
	}

	public mutating func select(row: Int) {
		guard visibleIndices.indices.contains(row) else { return }
		selection = row
	}

	/// Re-applies the current query after the history changed (e.g. an item was deleted),
	/// keeping the selection at the same visual position.
	public mutating func reload(clips: [Clip]) {
		visibleIndices = clips.indices.filter { HistoryFilter.matches(clips[$0], query: query) }
		if visibleIndices.isEmpty {
			selection = nil
		} else {
			selection = min(selection ?? 0, visibleIndices.count - 1)
		}
	}
}
