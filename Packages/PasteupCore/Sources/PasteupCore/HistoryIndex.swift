import Foundation

/// The on-disk format of `history.json`. Blob data lives in separate files next to it.
public struct HistoryIndex: Codable, Equatable, Sendable {
	public static let currentVersion = 1

	public enum DecodingError: Error, CustomStringConvertible {
		case unsupportedVersion(Int)

		public var description: String {
			switch self {
			case .unsupportedVersion(let version):
				"history.json has version \(version), but this app only reads version \(HistoryIndex.currentVersion)"
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

	public static func decode(_ data: Data) throws -> HistoryIndex {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		let index = try decoder.decode(HistoryIndex.self, from: data)
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
