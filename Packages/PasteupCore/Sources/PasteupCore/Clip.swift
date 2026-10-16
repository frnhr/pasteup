import Foundation

/// One representation of a pasteboard item (e.g. `public.utf8-plain-text`), stored as a blob on disk.
public struct Representation: Codable, Hashable, Sendable {
	public var type: String
	public var blobName: String
	public var byteCount: Int

	public init(type: String, blobName: String, byteCount: Int) {
		self.type = type
		self.blobName = blobName
		self.byteCount = byteCount
	}
}

/// One pasteboard item. A single copy can put several items on the pasteboard (e.g. several files in Finder).
public struct ClipItem: Codable, Hashable, Sendable {
	public var representations: [Representation]

	public init(representations: [Representation]) {
		self.representations = representations
	}
}

/// In-memory pasteboard data, used at capture and paste time. Never persisted as-is.
public struct RawRepresentation: Hashable, Sendable {
	public var type: String
	public var data: Data

	public init(type: String, data: Data) {
		self.type = type
		self.data = data
	}
}

public typealias RawItem = [RawRepresentation]

public struct SourceApp: Codable, Hashable, Sendable {
	public var bundleID: String?
	public var name: String?

	public init(bundleID: String?, name: String?) {
		self.bundleID = bundleID
		self.name = name
	}
}

public struct RGBAColor: Codable, Hashable, Sendable {
	public var red: Double
	public var green: Double
	public var blue: Double
	public var alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}
}

public struct PixelSize: Codable, Hashable, Sendable {
	public var width: Int
	public var height: Int

	public init(width: Int, height: Int) {
		self.width = width
		self.height = height
	}
}

/// Everything the picker row needs, computed once at capture time.
public struct ClipPreview: Codable, Hashable, Sendable {
	/// Collapsed, truncated text excerpt (see `PreviewText`).
	public var text: String?
	public var filePaths: [String]
	/// Size of the original image. Non-nil means a thumbnail was stored next to the blobs.
	public var imageSize: PixelSize?
	public var color: RGBAColor?
	/// All pasteboard types, for clips that have no better preview.
	public var types: [String]

	public init(
		text: String? = nil,
		filePaths: [String] = [],
		imageSize: PixelSize? = nil,
		color: RGBAColor? = nil,
		types: [String] = []
	) {
		self.text = text
		self.filePaths = filePaths
		self.imageSize = imageSize
		self.color = color
		self.types = types
	}
}

public struct Clip: Codable, Hashable, Identifiable, Sendable {
	public var id: UUID
	public var capturedAt: Date
	/// Hash over all representations (see `ContentHash`). Used for duplicate detection.
	public var contentHash: String
	public var items: [ClipItem]
	public var preview: ClipPreview
	/// Text the filter matches against: the plain text (capped) or the file names.
	public var searchText: String
	public var sourceApp: SourceApp?

	public init(
		id: UUID = UUID(),
		capturedAt: Date,
		contentHash: String,
		items: [ClipItem],
		preview: ClipPreview,
		searchText: String,
		sourceApp: SourceApp?
	) {
		self.id = id
		self.capturedAt = capturedAt
		self.contentHash = contentHash
		self.items = items
		self.preview = preview
		self.searchText = searchText
		self.sourceApp = sourceApp
	}

	public var types: Set<String> {
		Set(items.flatMap { $0.representations.map(\.type) })
	}
}
