// Draws the app icon and the menu bar icon from one glyph.
// The app icon is an Icon Composer document (AppIcon.icon): macOS draws its shape, fill and glass.
// Run with `make icons`.
import AppKit

let appFolder = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let catalog = appFolder.appending(path: "Assets.xcassets", directoryHint: .isDirectory)
let iconDocument = appFolder.appending(path: "AppIcon.icon", directoryHint: .isDirectory)

/// The glyph: list rows with an arrow from the bottom row back to the top,
/// because a pasted clip moves to the top of the history.
/// Drawn into `rect` in unit coordinates (0…1, y pointing down).
enum GlyphPart {
	case all, highlight, dimmed
}

func drawGlyph(in context: CGContext, rect: CGRect, color: NSColor, part: GlyphPart = .all) {
	context.saveGState()
	context.translateBy(x: rect.minX, y: rect.minY)
	context.scaleBy(x: rect.width, y: rect.height)

	func fill(_ path: CGPath, alpha: CGFloat) {
		context.setFillColor(color.withAlphaComponent(alpha).cgColor)
		context.addPath(path)
		context.fillPath()
	}

	let rowHeight: CGFloat = 0.16
	for (index, center) in [0.18, 0.5, 0.82].enumerated() {
		let isHighlight = index == 0
		guard part == .all || (part == .highlight) == isHighlight else { continue }
		let row = CGRect(x: 0.46, y: center - rowHeight / 2, width: 0.54, height: rowHeight)
		let path = CGPath(roundedRect: row, cornerWidth: rowHeight / 2, cornerHeight: rowHeight / 2, transform: nil)
		// A separate dimmed layer gets its opacity from the icon document instead.
		fill(path, alpha: isHighlight || part == .dimmed ? 1 : 0.45)
	}
	guard part != .dimmed else {
		context.restoreGState()
		return
	}

	let arrow = CGMutablePath()
	arrow.move(to: CGPoint(x: 0.33, y: 0.82))
	arrow.addLine(to: CGPoint(x: 0.19, y: 0.82))
	arrow.addArc(tangent1End: CGPoint(x: 0.06, y: 0.82), tangent2End: CGPoint(x: 0.06, y: 0.18), radius: 0.13)
	arrow.addArc(tangent1End: CGPoint(x: 0.06, y: 0.18), tangent2End: CGPoint(x: 0.3, y: 0.18), radius: 0.13)
	arrow.addLine(to: CGPoint(x: 0.22, y: 0.18))
	context.setStrokeColor(color.cgColor)
	context.setLineWidth(0.1)
	context.setLineCap(.round)
	context.setLineJoin(.round)
	context.addPath(arrow)
	context.strokePath()

	let head = CGMutablePath()
	head.move(to: CGPoint(x: 0.38, y: 0.18))
	head.addLine(to: CGPoint(x: 0.22, y: 0.05))
	head.addLine(to: CGPoint(x: 0.22, y: 0.31))
	head.closeSubpath()
	fill(head, alpha: 1)

	context.restoreGState()
}

/// One layer of the Icon Composer document: the glyph part in white on a transparent 1024 px canvas.
/// The icon fills the whole canvas, and macOS masks it to its rounded shape.
func renderIconLayer(_ part: GlyphPart) -> Data {
	let pixels = 1024
	let context = CGContext(
		data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
		space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	)!
	context.translateBy(x: 0, y: CGFloat(pixels))
	context.scaleBy(x: 1, y: -1)
	drawGlyph(in: context, rect: CGRect(x: 207, y: 207, width: 610, height: 610), color: .white, part: part)
	return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

/// An 18 pt vector PDF; the asset catalog marks it as a template so it follows the menu bar's color.
func writeMenuBarIcon(to url: URL) {
	var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
	let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil)!
	context.beginPDFPage(nil)
	context.translateBy(x: 0, y: 18)
	context.scaleBy(x: 1, y: -1)
	drawGlyph(in: context, rect: CGRect(x: 1, y: 1, width: 16, height: 16), color: .black)
	context.endPDFPage()
	context.closePDF()
}

func writeJSON(_ object: Any, to url: URL) throws {
	let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
	try data.write(to: url)
}

let info = ["author": "xcode", "version": 1] as [String: Any]
let menuBarFolder = catalog.appending(path: "MenuBarIcon.imageset", directoryHint: .isDirectory)
let iconAssets = iconDocument.appending(path: "Assets", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: menuBarFolder, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconAssets, withIntermediateDirectories: true)
try writeJSON(["info": info], to: catalog.appending(path: "Contents.json"))

writeMenuBarIcon(to: menuBarFolder.appending(path: "MenuBarIcon.pdf"))
try writeJSON([
	"images": [["filename": "MenuBarIcon.pdf", "idiom": "universal"]],
	"info": info,
	"properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
], to: menuBarFolder.appending(path: "Contents.json"))

try renderIconLayer(.highlight).write(to: iconAssets.appending(path: "highlight.png"))
try renderIconLayer(.dimmed).write(to: iconAssets.appending(path: "rows.png"))
func layer(_ name: String, opacity: Double) -> [String: Any] {
	[
		"image-name": "\(name).png",
		"name": name,
		"opacity": opacity,
		"position": ["scale": 1, "translation-in-points": [0, 0]],
	]
}
try writeJSON([
	"fill": ["automatic-gradient": "extended-srgb:0.27000,0.37000,0.90000,1.00000"],
	"groups": [[
		"layers": [layer("highlight", opacity: 1), layer("rows", opacity: 0.5)],
		"shadow": ["kind": "neutral", "opacity": 0.5],
		"specular": true,
		"translucency": ["enabled": true, "value": 0.5],
	]],
	"supported-platforms": ["squares": "shared"],
], to: iconDocument.appending(path: "icon.json"))

print("Wrote \(iconDocument.path) and the menu bar icon in \(catalog.path)")
