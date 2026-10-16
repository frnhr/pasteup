import PasteupCore
import SwiftUI

struct PickerView: View {
	static let size = CGSize(width: 560, height: 440)

	@Bindable var model: PickerModel
	let images: ImageCache
	@FocusState private var isFilterFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			TextField("Type to filter", text: $model.query)
				.textFieldStyle(.plain)
				.font(.title3)
				.padding(.horizontal, 14)
				.padding(.vertical, 12)
				.focused($isFilterFocused)
			Divider()
			if model.state.visibleIndices.isEmpty {
				emptyState
			} else {
				list
			}
			Divider()
			footer
		}
		.frame(width: Self.size.width, height: Self.size.height)
		.background(.regularMaterial)
		.onAppear {
			isFilterFocused = true
		}
	}

	private var list: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(spacing: 2) {
					ForEach(Array(model.state.visibleIndices.enumerated()), id: \.element) { row, index in
						let clip = model.clips[index]
						ClipRowView(
							clip: clip,
							number: index + 1,
							isSelected: row == model.state.selection,
							images: images
						)
						.id(clip.id)
						.onTapGesture(count: 2) {
							model.paste(row: row)
						}
						.onTapGesture {
							model.select(row: row)
						}
					}
				}
				.padding(6)
			}
			.onChange(of: model.state.selectedClipIndex, initial: true) { _, index in
				guard let index, model.clips.indices.contains(index) else { return }
				proxy.scrollTo(model.clips[index].id)
			}
		}
	}

	private var emptyState: some View {
		Text(model.clips.isEmpty ? "No clips yet. Copy something!" : "No matches")
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var footer: some View {
		HStack(spacing: 14) {
			Text("↩ Paste")
			Text("⇧↩ Paste as plain text")
			Text("⌘⌫ Delete")
			Spacer()
			Text("esc Close")
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 14)
		.padding(.vertical, 6)
	}
}
