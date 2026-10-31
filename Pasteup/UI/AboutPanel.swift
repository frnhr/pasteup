import AppKit

/// The standard About panel (icon, name, version, copyright) with a one-line description, the developer, and the
/// licenses of the app and the library it uses.
enum AboutPanel {
	static func show() {
		// A menu bar app isn't active, so the panel would otherwise open behind other windows.
		NSApp.activate()
		NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
	}

	private static var credits: NSAttributedString {
		let credits = NSMutableAttributedString()
		credits.append(text("Copy several things, then paste them back one by one, in the order you copied them.\n\n"))
		credits.append(text("Developed by Fran Hrženjak\n"))
		credits.append(text("Uses KeyboardShortcuts by Sindre Sorhus\n\n", size: 10, color: .tertiaryLabelColor))
		credits.append(text("Pasteup is licensed under the MIT License.\n"))
		// The same notice as in LICENSE.
		credits.append(text("Copyright (c) 2026 Fran Hrženjak <fran.hrzenjak@gmail.com> (https://changeset.hr)\n\n"))
		credits.append(text("KeyboardShortcuts is licensed under the MIT License.\n"))
		// Its license requires this copyright notice, word for word, in every copy of the app.
		credits.append(text("Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)\n\n"))
		credits.append(text("MIT License\n", weight: .semibold))
		credits.append(text(mitLicense))
		return credits
	}

	private static func text(
		_ string: String,
		size: CGFloat = NSFont.smallSystemFontSize,
		weight: NSFont.Weight = .regular,
		color: NSColor = .secondaryLabelColor
	) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		return NSAttributedString(
			string: string,
			attributes: [
				.font: NSFont.systemFont(ofSize: size, weight: weight),
				.foregroundColor: color,
				.paragraphStyle: paragraph,
			]
		)
	}

	/// The MIT License below its copyright line, word for word. Pasteup's LICENSE file and KeyboardShortcuts 3.1.0
	/// use the same text.
	private static let mitLicense = """
		Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
		documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
		the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to \
		permit persons to whom the Software is furnished to do so, subject to the following conditions:

		The above copyright notice and this permission notice shall be included in all copies or substantial portions \
		of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO \
		THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
		AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, \
		TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
		"""
}
