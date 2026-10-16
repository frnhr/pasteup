import Foundation
@testable import PasteupCore

let epoch = Date(timeIntervalSince1970: 1_000_000)

/// A text clip whose content hash is derived from its text, captured `seconds` after `epoch`.
func textClip(_ text: String, at seconds: TimeInterval = 0) -> Clip {
	Clip(
		capturedAt: epoch.addingTimeInterval(seconds),
		contentHash: "hash-\(text)",
		items: [ClipItem(representations: [
			Representation(type: "public.utf8-plain-text", blobName: "0-0.bin", byteCount: text.utf8.count)
		])],
		preview: ClipPreview(text: text, types: ["public.utf8-plain-text"]),
		searchText: text,
		sourceApp: SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")
	)
}

extension ClipHistory {
	/// Previews (texts) of all clips, top first.
	var texts: [String] {
		clips.map { $0.preview.text ?? "?" }
	}

	/// Captures each text, one copy every 10 seconds (well outside the duplicate window).
	static func copied(_ texts: [String]) -> ClipHistory {
		var history = ClipHistory()
		for (offset, text) in texts.enumerated() {
			_ = history.capture(textClip(text, at: TimeInterval(offset * 10)))
		}
		return history
	}
}
