import PasteupCore
import SwiftUI

struct PickerView: View {
	static let size = CGSize(width: 560, height: 440)

	@Bindable var model: PickerModel
	@FocusState private var isFilterFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				TextField("Type to filter", text: $model.query)
					.textFieldStyle(.plain)
					.font(.title3)
					.focused($isFilterFocused)
				listTabs
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 10)
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
		.onChange(of: model.list) {
			// Clicking a tab must not leave the filter without keyboard focus.
			isFilterFocused = true
		}
	}

	private var listTabs: some View {
		Picker("List", selection: Binding(get: { model.list }, set: { model.show($0) })) {
			Text("History").tag(ClipList.history)
			Text("Saved").tag(ClipList.saved)
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.fixedSize()
		.help("← → to switch")
	}

	private var list: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(spacing: 2) {
					// Keyed by clip ID, so a row never shows a stale clip after the list changes.
					ForEach(visibleRows, id: \.clip.id) { visible in
						ClipRowView(
							clip: visible.clip,
							number: visible.index + 1,
							isSelected: visible.row == model.state.selection,
							saveButton: saveButton(for: visible.clip),
							images: model.images,
							onToggleSaved: { model.toggleSaved(row: visible.row) }
						)
						.onTapGesture(count: 2) {
							model.paste(row: visible.row)
						}
						.onTapGesture {
							model.select(row: visible.row)
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
		// A fresh scroll view per list, so switching lists doesn't carry over the scroll position.
		.id(model.list)
	}

	/// `row` is the position in the filtered list, `index` the position in the full list.
	private var visibleRows: [(row: Int, index: Int, clip: Clip)] {
		model.state.visibleIndices.enumerated().map { row, index in
			(row: row, index: index, clip: model.clips[index])
		}
	}

	private func saveButton(for clip: Clip) -> ClipRowView.SaveButton {
		switch model.list {
		case .history: model.isSaved(clip) ? .saved : .save
		case .saved: .unsave
		}
	}

	private var emptyState: some View {
		Group {
			if !model.clips.isEmpty {
				Text("No matches")
			} else if model.list == .history {
				Text("No clips yet. Copy something!")
			} else {
				Text("No saved clips yet. To save one, click \(Image(systemName: "bookmark")) on a clip in History, or press ⌘S.")
			}
		}
		.foregroundStyle(.secondary)
		.multilineTextAlignment(.center)
		.padding(.horizontal, 40)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var footer: some View {
		HStack(spacing: 14) {
			Text("↩ Paste")
			Text("⇧↩ Plain text")
			Text(model.list == .history ? "⌘S Save" : "⌘S Unsave")
			if model.list == .history {
				Text("⌘⌫ Delete")
			}
			Text("← → Switch list")
			Spacer()
			Text("esc Close")
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 14)
		.padding(.vertical, 6)
	}
}
