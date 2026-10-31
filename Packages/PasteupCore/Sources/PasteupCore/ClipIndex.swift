import Foundation

/// The on-disk format of a clip list's index (`history.json`, `saved.json`). Blob data lives in separate files
/// next to it.
public struct ClipIndex: Codable, Equatable, Sendable {
	public static let currentVersion = 1

	public enum DecodingError: Error, CustomStringConvertible {
		case unsupportedVersion(Int)

		public var description: String {
			switch self {
			case .unsupportedVersion(let version):
				"The index has version \(version), but this app only reads version \(ClipIndex.currentVersion)"
			}
		}
	}

	public var version: Int
	public var stickyRow: Int
	public var clips: [Clip]

	public init(history: ClipHistory) {
		version = Self.currentVersion
		stickyRow = history.stickyRow
		clips = history.clips
	}

	public init(saved: SavedClips) {
		version = Self.currentVersion
		stickyRow = saved.stickyRow
		clips = saved.clips
	}

	public static func decode(_ data: Data) throws -> ClipIndex {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		let index = try decoder.decode(ClipIndex.self, from: data)
		guard index.version == currentVersion else {
			throw DecodingError.unsupportedVersion(index.version)
		}
		return index
	}

	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		encoder.outputFormatting = [.sortedKeys]
		return try encoder.encode(self)
	}
}
