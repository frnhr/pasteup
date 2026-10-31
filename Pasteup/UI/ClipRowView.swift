import PasteupCore
import SwiftUI

struct ClipRowView: View {
	enum SaveButton {
		/// A history clip that isn't saved: the button saves it and shows only while the row is highlighted.
		case save
		/// A history clip that is saved: the button is always shown and unsaves it.
		case saved
		/// A clip in the saved list: the button unsaves it and shows only while the row is highlighted.
		case unsave
	}

	let clip: Clip
	/// 1-based position in the full list (not the filtered one), so the sticky row is easy to follow.
	let number: Int
	let isSelected: Bool
	let saveButton: SaveButton
	let images: ImageCache
	let onToggleSaved: () -> Void

	@State private var isHovered = false
	@State private var isButtonHovered = false

	var body: some View {
		HStack(spacing: 10) {
			Text("\(number)")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(width: 26, alignment: .trailing)
			content
				.frame(maxWidth: .infinity, alignment: .leading)
			metadata
			saveToggle
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.frame(minHeight: 44)
		.background(
			RoundedRectangle(cornerRadius: 6)
				.fill(isSelected ? Color.accentColor.opacity(0.28) : .clear)
		)
		.contentShape(Rectangle())
		.onHover { isHovered = $0 }
	}

	private var saveToggle: some View {
		let isVisible = saveButton == .saved || isSelected || isHovered
		let symbol = switch saveButton {
		case .save: "bookmark"
		case .saved: isButtonHovered ? "bookmark.slash" : "bookmark.fill"
		case .unsave: "bookmark.slash"
		}
		return Button(action: onToggleSaved) {
			Image(systemName: symbol)
				.font(.body)
				.foregroundStyle(saveButton == .saved && !isButtonHovered ? Color.accentColor : .secondary)
				.frame(width: 20, height: 28)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(saveButton == .save ? "Save (⌘S)" : "Unsave (⌘S)")
		.onHover { isButtonHovered = $0 }
		// Hidden, not removed, so the row layout doesn't shift on hover.
		.opacity(isVisible ? 1 : 0)
		.allowsHitTesting(isVisible)
	}

	@ViewBuilder
	private var content: some View {
		let preview = clip.preview
		if !preview.filePaths.isEmpty {
			files(preview.filePaths)
		} else {
			HStack(spacing: 10) {
				if preview.imageSize != nil, let thumbnail = images.thumbnail(for: clip.id) {
					let size = Self.thumbnailSize(for: thumbnail.size)
					Image(nsImage: thumbnail)
						.resizable()
						.frame(width: size.width, height: size.height)
						.clipShape(RoundedRectangle(cornerRadius: 4))
				}
				if let text = preview.text, !text.isEmpty {
					Text(text)
						.lineLimit(2)
						.truncationMode(.tail)
				} else if let size = preview.imageSize {
					Text("Image \(size.width) × \(size.height)")
						.foregroundStyle(.secondary)
				} else if let color = preview.color {
					colorSwatch(color)
				} else {
					Text(preview.types.joined(separator: ", "))
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
		}
	}

	/// Scales the thumbnail to fit 120 × 48 pt, so a narrow image doesn't reserve the full width.
	private static func thumbnailSize(for size: NSSize) -> CGSize {
		let scale = min(120 / size.width, 48 / size.height)
		return CGSize(width: size.width * scale, height: size.height * scale)
	}

	private func files(_ paths: [String]) -> some View {
		HStack(spacing: 8) {
			Image(nsImage: images.fileIcon(path: paths[0]))
				.resizable()
				.frame(width: 32, height: 32)
			VStack(alignment: .leading, spacing: 2) {
				Text(paths.count == 1 ? (paths[0] as NSString).lastPathComponent : "\(paths.count) files")
					.lineLimit(1)
				Text(paths.count == 1 ? (paths[0] as NSString).deletingLastPathComponent : paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
	}

	private func colorSwatch(_ color: RGBAColor) -> some View {
		HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 4)
				.fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
				.frame(width: 32, height: 32)
				.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
			Text(String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255)))
				.font(.body.monospaced())
		}
	}

	private var metadata: some View {
		VStack(alignment: .trailing, spacing: 2) {
			if let bundleID = clip.sourceApp?.bundleID, let icon = images.appIcon(bundleID: bundleID) {
				Image(nsImage: icon)
					.resizable()
					.frame(width: 16, height: 16)
					.help(clip.sourceApp?.name ?? bundleID)
			}
			Text(clip.capturedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
}
