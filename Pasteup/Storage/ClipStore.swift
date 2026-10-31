import Foundation
import PasteupCore
import os

private let logger = Logger(subsystem: "com.franhrzenjak.pasteup", category: "store")

/// On-disk storage of one clip list. The history lives in Application Support/Pasteup, the saved clips in its
/// `saved` subfolder, each with its own index and blobs:
///
///     history.json             the index (see `ClipIndex`); `saved.json` for the saved clips
///     blobs/<clip-id>/0-0.bin  one file per pasteboard representation
///     blobs/<clip-id>/thumb.png
final class ClipStore {
	static let historyDirectory = URL.applicationSupportDirectory.appending(path: "Pasteup", directoryHint: .isDirectory)
	static let savedDirectory = historyDirectory.appending(path: "saved", directoryHint: .isDirectory)

	let directory: URL
	private let indexName: String
	private let fileManager = FileManager.default

	private var indexURL: URL {
		directory.appending(path: indexName)
	}

	private var blobsDirectory: URL {
		directory.appending(path: "blobs", directoryHint: .isDirectory)
	}

	init(directory: URL, indexName: String) {
		self.directory = directory
		self.indexName = indexName
	}

	func prepare() throws {
		try fileManager.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
	}

	/// Returns nil when there is no history yet.
	func loadIndex() throws -> ClipIndex? {
		guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
		return try ClipIndex.decode(Data(contentsOf: indexURL))
	}

	func saveIndex(_ index: ClipIndex) throws {
		try index.encoded().write(to: indexURL, options: .atomic)
	}

	/// Moves an unreadable index and its blobs into `corrupt-<timestamp>/`, so nothing is lost
	/// and the app can start fresh. Returns the folder.
	func quarantineIndex() throws -> URL {
		let timestamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
		let folder = directory.appending(path: "corrupt-\(timestamp)", directoryHint: .isDirectory)
		try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
		try fileManager.moveItem(at: indexURL, to: folder.appending(path: indexName))
		try fileManager.moveItem(at: blobsDirectory, to: folder.appending(path: "blobs", directoryHint: .isDirectory))
		try prepare()
		return folder
	}

	func writeBlobs(of clip: Clip, items: [RawItem], thumbnail: Data?) throws {
		let folder = blobFolder(for: clip.id)
		try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
		for (item, record) in zip(items, clip.items) {
			for (representation, stored) in zip(item, record.representations) {
				try representation.data.write(to: folder.appending(path: stored.blobName))
			}
		}
		if let thumbnail {
			try thumbnail.write(to: thumbnailURL(for: clip.id))
		}
	}

	/// Copies the blobs of `clip` into `other` under `newID` (a clone on APFS, so it costs no extra space).
	func copyBlobs(of clip: Clip, to other: ClipStore, as newID: UUID) throws {
		try fileManager.copyItem(at: blobFolder(for: clip.id), to: other.blobFolder(for: newID))
	}

	func readItems(of clip: Clip) throws -> [RawItem] {
		try clip.items.map { record in
			try record.representations.map { stored in
				RawRepresentation(type: stored.type, data: try readData(of: clip, representation: stored))
			}
		}
	}

	func readData(of clip: Clip, representation: Representation) throws -> Data {
		try Data(contentsOf: blobFolder(for: clip.id).appending(path: representation.blobName))
	}

	func thumbnailURL(for clipID: UUID) -> URL {
		blobFolder(for: clipID).appending(path: "thumb.png")
	}

	/// Cleanup only: a failure leaves stray files behind but loses nothing, so it's logged, not raised.
	func removeBlobs(ofClipIDs clipIDs: [UUID]) {
		for clipID in clipIDs {
			let folder = blobFolder(for: clipID)
			guard fileManager.fileExists(atPath: folder.path) else { continue }
			do {
				try fileManager.removeItem(at: folder)
			} catch {
				logger.error("Failed to remove blobs of \(clipID): \(error)")
			}
		}
	}

	/// Removes blob folders left behind by a crash between writing blobs and saving the index.
	func removeOrphanBlobs(keeping clipIDs: Set<UUID>) {
		let folders: [URL]
		do {
			folders = try fileManager.contentsOfDirectory(at: blobsDirectory, includingPropertiesForKeys: nil)
		} catch {
			logger.error("Failed to list blobs: \(error)")
			return
		}
		let orphans = folders.compactMap { UUID(uuidString: $0.lastPathComponent) }.filter { !clipIDs.contains($0) }
		if !orphans.isEmpty {
			logger.info("Removing \(orphans.count) orphaned blob folders")
		}
		removeBlobs(ofClipIDs: orphans)
	}

	private func blobFolder(for clipID: UUID) -> URL {
		blobsDirectory.appending(path: clipID.uuidString, directoryHint: .isDirectory)
	}
}
