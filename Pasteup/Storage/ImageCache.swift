import AppKit

/// Thumbnails, file icons, and app icons for the picker rows, loaded on first use.
final class ImageCache {
	private let store: ClipStore
	private var thumbnails: [UUID: NSImage] = [:]
	private var appIcons: [String: NSImage] = [:]

	init(store: ClipStore) {
		self.store = store
	}

	func thumbnail(for clipID: UUID) -> NSImage? {
		if let cached = thumbnails[clipID] {
			return cached
		}
		let image = NSImage(contentsOf: store.thumbnailURL(for: clipID))
		thumbnails[clipID] = image
		return image
	}

	func appIcon(bundleID: String) -> NSImage? {
		if let cached = appIcons[bundleID] {
			return cached
		}
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
		let icon = NSWorkspace.shared.icon(forFile: url.path)
		appIcons[bundleID] = icon
		return icon
	}

	/// File icons are cheap and cached by the system already.
	func fileIcon(path: String) -> NSImage {
		NSWorkspace.shared.icon(forFile: path)
	}

	func forget(clipIDs: [UUID]) {
		for clipID in clipIDs {
			thumbnails[clipID] = nil
		}
	}
}
