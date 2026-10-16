import AppKit

/// The standard About panel (icon, name, version, copyright) with a one-line description.
enum AboutPanel {
	static func show() {
		// A menu bar app isn't active, so the panel would otherwise open behind other windows.
		NSApp.activate()
		NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
	}

	private static var credits: NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		return NSAttributedString(
			string: "Copy several things, then paste them back one by one, in the order you copied them.",
			attributes: [
				.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
				.foregroundColor: NSColor.secondaryLabelColor,
				.paragraphStyle: paragraph,
			]
		)
	}
}
