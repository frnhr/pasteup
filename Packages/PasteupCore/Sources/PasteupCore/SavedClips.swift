import Foundation

/// Clips the user saved to keep. Unlike the history, the list has no size limit and no duplicates: clips are keyed
/// by content hash, which is also how a history clip shows whether it's saved.
///
/// A saved clip is a copy with its own ID and blobs, so deleting or evicting the history clip it came from
/// doesn't affect it. Pasting follows the same sticky-row rule as the history (see `ClipHistory`).
public struct SavedClips: Sendable {
	public private(set) var clips: [Clip]
	public private(set) var stickyRow: Int
	private var contentHashes: Set<String>

	/// Drops all but the first clip of each content hash, so a hand-edited or old file can't break the rule.
	public init(clips: [Clip] = [], stickyRow: Int = 0) {
		var seen = Set<String>()
		self.clips = clips.filter { seen.insert($0.contentHash).inserted }
		contentHashes = seen
		self.stickyRow = max(0, min(stickyRow, self.clips.count - 1))
	}

	/// The row to highlight when the list is shown.
	public var initialSelection: Int? {
		clips.isEmpty ? nil : min(stickyRow, clips.count - 1)
	}

	public func contains(contentHash: String) -> Bool {
		contentHashes.contains(contentHash)
	}

	/// Adds the clip at the top and resets the sticky row, like a new copy does in the history.
	/// Returns false (and changes nothing) if a clip with the same content is already saved.
	public mutating func save(_ clip: Clip) -> Bool {
		guard contentHashes.insert(clip.contentHash).inserted else { return false }
		clips.insert(clip, at: 0)
		stickyRow = 0
		return true
	}

	/// Moves the clip at `index` to the top and remembers `index` as the sticky row.
	@discardableResult
	public mutating func paste(at index: Int) -> Clip {
		precondition(clips.indices.contains(index), "paste index \(index) out of range 0..<\(clips.count)")
		let clip = clips.remove(at: index)
		clips.insert(clip, at: 0)
		stickyRow = index
		return clip
	}

	/// Moves a stable ID before another ID, or to the end for nil. Missing IDs are a no-op.
	/// Arranging selects and remembers the moved clip; subsequent pastes retain the sticky-row rule.
	@discardableResult
	public mutating func move(_ id: Clip.ID, before destination: Clip.ID?) -> Bool {
		guard id != destination, let source = clips.firstIndex(where: { $0.id == id }),
		      destination == nil || clips.contains(where: { $0.id == destination }) else { return false }
		let clip = clips.remove(at: source)
		let target = destination.flatMap { id in clips.firstIndex { $0.id == id } } ?? clips.count
		clips.insert(clip, at: target)
		stickyRow = target
		return true
	}

	@discardableResult
	public mutating func delete(at index: Int) -> Clip {
		precondition(clips.indices.contains(index), "delete index \(index) out of range 0..<\(clips.count)")
		let clip = clips.remove(at: index)
		contentHashes.remove(clip.contentHash)
		stickyRow = max(0, min(stickyRow, clips.count - 1))
		return clip
	}

	/// Removes the saved clip with this content, if any.
	public mutating func delete(contentHash: String) -> Clip? {
		guard let index = clips.firstIndex(where: { $0.contentHash == contentHash }) else { return nil }
		return delete(at: index)
	}
}
