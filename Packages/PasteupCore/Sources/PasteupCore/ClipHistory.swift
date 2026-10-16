import Foundation

/// The clip stack and the sticky-row rule.
///
/// Sticky row: pasting the clip at row k moves it to the top and remembers k. The next time the picker
/// opens, row k is highlighted again (now a different clip), unless a new copy happened in between,
/// which resets the sticky row to 0. Repeated hotkey → Enter therefore pastes the history in copy order.
public struct ClipHistory: Sendable {
	/// A copy identical to the top clip within this many seconds of the previous copy is skipped.
	public static let duplicateWindow: TimeInterval = 2
	public static let defaultCapacity = 50

	public enum CaptureResult: Equatable, Sendable {
		case inserted(evicted: [Clip])
		case skippedDuplicate
	}

	private struct CopyEvent: Sendable {
		var contentHash: String
		var date: Date
	}

	public private(set) var clips: [Clip]
	public private(set) var stickyRow: Int
	public private(set) var capacity: Int
	/// Last external copy, including skipped duplicates, so the window slides with repeated copies.
	private var lastCopy: CopyEvent?

	/// Does not trim; call `setCapacity(_:)` afterwards to apply the configured size.
	public init(clips: [Clip] = [], stickyRow: Int = 0) {
		self.clips = clips
		self.capacity = Self.defaultCapacity
		self.stickyRow = max(0, min(stickyRow, clips.count - 1))
	}

	/// The row to highlight when the picker opens.
	public var initialSelection: Int? {
		clips.isEmpty ? nil : min(stickyRow, clips.count - 1)
	}

	public func index(of id: Clip.ID) -> Int? {
		clips.firstIndex { $0.id == id }
	}

	/// A copy made by the user in another app.
	public mutating func capture(_ clip: Clip) -> CaptureResult {
		defer { lastCopy = CopyEvent(contentHash: clip.contentHash, date: clip.capturedAt) }
		if let lastCopy,
		   lastCopy.contentHash == clip.contentHash,
		   clip.capturedAt.timeIntervalSince(lastCopy.date) < Self.duplicateWindow,
		   clips.first?.contentHash == clip.contentHash {
			return .skippedDuplicate
		}
		return .inserted(evicted: insertAtTop(clip))
	}

	/// The clipboard content found at app launch, which may have been copied while the app wasn't running.
	public mutating func captureAtLaunch(_ clip: Clip) -> CaptureResult {
		defer { lastCopy = CopyEvent(contentHash: clip.contentHash, date: clip.capturedAt) }
		if clips.first?.contentHash == clip.contentHash {
			return .skippedDuplicate
		}
		return .inserted(evicted: insertAtTop(clip))
	}

	/// Moves the clip at `index` (full-list index) to the top and remembers `index` as the sticky row.
	@discardableResult
	public mutating func paste(at index: Int) -> Clip {
		precondition(clips.indices.contains(index), "paste index \(index) out of range 0..<\(clips.count)")
		let clip = clips.remove(at: index)
		clips.insert(clip, at: 0)
		stickyRow = index
		return clip
	}

	@discardableResult
	public mutating func delete(at index: Int) -> Clip {
		precondition(clips.indices.contains(index), "delete index \(index) out of range 0..<\(clips.count)")
		let clip = clips.remove(at: index)
		stickyRow = clampedRow(stickyRow)
		return clip
	}

	/// Returns the clips evicted by a smaller capacity.
	public mutating func setCapacity(_ newCapacity: Int) -> [Clip] {
		precondition(newCapacity >= 1, "capacity must be at least 1")
		capacity = newCapacity
		return trimToCapacity()
	}

	public mutating func removeAll() -> [Clip] {
		let removed = clips
		clips = []
		stickyRow = 0
		return removed
	}

	private mutating func insertAtTop(_ clip: Clip) -> [Clip] {
		clips.insert(clip, at: 0)
		stickyRow = 0
		return trimToCapacity()
	}

	private mutating func trimToCapacity() -> [Clip] {
		guard clips.count > capacity else { return [] }
		let evicted = Array(clips[capacity...])
		clips.removeLast(clips.count - capacity)
		stickyRow = clampedRow(stickyRow)
		return evicted
	}

	private func clampedRow(_ row: Int) -> Int {
		max(0, min(row, clips.count - 1))
	}
}
