import Foundation

public enum PreviewText {
	/// Rows show at most two lines, so a few hundred characters is plenty.
	public static let excerptLength = 300
	/// Cap on the text kept for filtering, so a huge copied log doesn't bloat `history.json`.
	public static let searchLength = 20_000

	/// Collapses all whitespace runs (including newlines) into single spaces, trims, and truncates.
	public static func excerpt(from text: String) -> String {
		let collapsed = text
			.split(whereSeparator: { $0.isWhitespace })
			.joined(separator: " ")
		guard collapsed.count > excerptLength else { return collapsed }
		return String(collapsed.prefix(excerptLength)) + "…"
	}

	public static func searchable(from text: String) -> String {
		String(text.prefix(searchLength))
	}
}
