// Renders the promo overlay track from events.json: captions, keycaps, numbered badges and the end card.
// The result is a transparent 1920 × 1080, 30 fps ProRes 4444 movie that compose.sh lays over the recording.
//
// Usage: render <events.json> <icon.png> <appstore|web> <output.mov>
import AppKit
import AVFoundation

struct Failure: Error, CustomStringConvertible {
	let description: String
}

// MARK: - Input

struct Event: Decodable {
	enum Kind: String, Decodable {
		case keys, copy, paste, done
	}

	let time: Double
	let kind: Kind
	let label: String?
	let number: Int?
	let rect: CGRect?
}

struct TakeLog: Decodable {
	let regionSize: CGSize
	let events: [Event]
}

let arguments = CommandLine.arguments
guard arguments.count == 5, ["appstore", "web"].contains(arguments[3]) else {
	FileHandle.standardError.write(Data("usage: render <events.json> <icon.png> <appstore|web> <output.mov>\n".utf8))
	exit(2)
}
let log = try JSONDecoder().decode(TakeLog.self, from: Data(contentsOf: URL(filePath: arguments[1])))
guard let icon = NSImage(contentsOfFile: arguments[2]) else {
	throw Failure(description: "Can't read the icon at \(arguments[2]).")
}
let isWeb = arguments[3] == "web"
let outputURL = URL(filePath: arguments[4])

// MARK: - Timeline

let size = CGSize(width: 1920, height: 1080)
let frameRate = 30
/// Recorded points to video pixels.
let scale = size.width / log.regionSize.width

guard let done = log.events.first(where: { $0.kind == .done })?.time else {
	throw Failure(description: "events.json has no done event.")
}
let keys = log.events.filter { $0.kind == .keys }
let copies = log.events.filter { $0.kind == .copy }
let pastes = log.events.filter { $0.kind == .paste }
let pickerOpenings = keys.filter { $0.label == "⌃⌘V" }.map(\.time)
guard copies.count == 5, pastes.count == 5, pickerOpenings.count == 5, let lastCopy = copies.last?.time else {
	throw Failure(description: "events.json doesn't have 5 copies, 5 pickers and 5 pastes.")
}

/// The end card fades in over the last moment of the recording.
let endCardStart = done - 0.2
let endCardFade = 0.5
let duration = done + 3.4

struct Caption {
	let text: String
	let start: Double
	let end: Double
}

let captions = [
	Caption(text: "Copy what you need, in order.", start: 0.3, end: lastCopy + 1.0),
	Caption(text: "Paste them back, one by one.", start: lastCopy + 1.4, end: endCardStart),
]

// MARK: - Drawing helpers

func clamp(_ value: Double) -> Double {
	min(1, max(0, value))
}

func easeOut(_ progress: Double) -> Double {
	1 - pow(1 - clamp(progress), 3)
}

/// Opacity of something shown from `start` to `end`, fading in and out.
func visibility(_ time: Double, start: Double, end: Double, fadeIn: Double, fadeOut: Double) -> Double {
	guard time >= start, time <= end else { return 0 }
	let rising = fadeIn > 0 ? clamp((time - start) / fadeIn) : 1
	let falling = fadeOut > 0 ? clamp((end - time) / fadeOut) : 1
	return min(rising, falling)
}

let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let brand = NSColor(srgbRed: 0.27, green: 0.37, blue: 0.90, alpha: 1)

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
	NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

/// Draws text centered on `center`, faded and offset.
func drawCentered(_ text: NSAttributedString, center: CGPoint, alpha: Double, in context: CGContext) {
	guard alpha > 0 else { return }
	let textSize = text.size()
	context.saveGState()
	context.setAlpha(alpha)
	text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
	context.restoreGState()
}

func drawKeycap(_ label: String, alpha: Double, popIn: Double, in context: CGContext) {
	guard alpha > 0 else { return }
	let text = attributed(label, size: 40, weight: .semibold, color: .white)
	let textSize = text.size()
	let chip = CGSize(width: max(textSize.width + 56, 96), height: textSize.height + 26)
	let center = CGPoint(x: size.width / 2, y: size.height - 96)
	let chipScale = 0.92 + 0.08 * easeOut(popIn)
	context.saveGState()
	context.setAlpha(alpha)
	context.translateBy(x: center.x, y: center.y)
	context.scaleBy(x: chipScale, y: chipScale)
	let frame = CGRect(x: -chip.width / 2, y: -chip.height / 2, width: chip.width, height: chip.height)
	context.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
	context.addPath(CGPath(roundedRect: frame, cornerWidth: 16, cornerHeight: 16, transform: nil))
	context.setFillColor(NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.88).cgColor)
	context.fillPath()
	context.setShadow(offset: .zero, blur: 0)
	text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
	context.restoreGState()
}

/// A numbered circle at the right end of a cell, popping in when it appears.
func drawBadge(_ number: Int, cell: CGRect, appeared: Double, alpha: Double, in context: CGContext) {
	guard alpha > 0, appeared >= 0 else { return }
	let pop = appeared < 0.12 ? 0.4 + 0.75 * (appeared / 0.12) : 1.15 - 0.15 * clamp((appeared - 0.12) / 0.13)
	let diameter: CGFloat = 28
	let center = CGPoint(x: (cell.maxX - 13) * scale, y: cell.midY * scale)
	context.saveGState()
	context.setAlpha(alpha * clamp(appeared / 0.08))
	context.translateBy(x: center.x, y: center.y)
	context.scaleBy(x: pop, y: pop)
	context.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: NSColor.black.withAlphaComponent(0.3).cgColor)
	context.addEllipse(in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
	context.setFillColor(brand.cgColor)
	context.fillPath()
	context.setShadow(offset: .zero, blur: 0)
	let text = attributed("\(number)", size: 18, weight: .bold, color: .white)
	let textSize = text.size()
	text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
	context.restoreGState()
}

func drawEndCard(progress: Double, elapsed: Double, in context: CGContext) {
	guard progress > 0 else { return }
	context.saveGState()
	context.setAlpha(progress)
	let gradient = CGGradient(
		colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
		colors: [
			NSColor(srgbRed: 0.95, green: 0.96, blue: 0.99, alpha: 1).cgColor,
			NSColor(srgbRed: 0.83, green: 0.87, blue: 0.97, alpha: 1).cgColor,
		] as CFArray,
		locations: [0, 1]
	)!
	context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

	let iconSize: CGFloat = 260
	let iconScale = 0.94 + 0.06 * easeOut(elapsed / 0.6)
	let iconFrame = CGRect(
		x: size.width / 2 - iconSize * iconScale / 2,
		y: 250 - iconSize * iconScale / 2 + iconSize / 2,
		width: iconSize * iconScale,
		height: iconSize * iconScale
	)
	icon.draw(in: iconFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

	drawCentered(attributed("Pasteup", size: 92, weight: .bold, color: ink), center: CGPoint(x: size.width / 2, y: 640), alpha: easeOut((elapsed - 0.15) / 0.4), in: context)
	drawCentered(
		attributed("Copy in order. Paste in order.", size: 44, weight: .medium, color: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)),
		center: CGPoint(x: size.width / 2, y: 728),
		alpha: easeOut((elapsed - 0.35) / 0.4),
		in: context
	)
	if isWeb {
		drawCentered(
			attributed("Free and open source · github.com/frnhr/pasteup", size: 30, weight: .regular, color: NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)),
			center: CGPoint(x: size.width / 2, y: 812),
			alpha: easeOut((elapsed - 0.55) / 0.4),
			in: context
		)
	}
	context.restoreGState()
}

func drawFrame(at time: Double, in context: CGContext) {
	for caption in captions {
		let alpha = visibility(time, start: caption.start, end: caption.end, fadeIn: 0.35, fadeOut: 0.3)
		let rise = 14 * (1 - easeOut((time - caption.start) / 0.35))
		drawCentered(attributed(caption.text, size: 46, weight: .semibold, color: ink), center: CGPoint(x: size.width / 2, y: 96 + rise), alpha: alpha, in: context)
	}

	// Keycaps: each shows until the next key or for a second; quick successions swap without fading.
	for (index, event) in keys.enumerated() {
		let next = index + 1 < keys.count ? keys[index + 1].time : .infinity
		let end = min(next, event.time + 1.0)
		let followsClosely = index > 0 && event.time - keys[index - 1].time < 1.0
		let alpha = visibility(time, start: event.time, end: end, fadeIn: followsClosely ? 0 : 0.1, fadeOut: next <= event.time + 1.0 ? 0 : 0.2)
		drawKeycap(event.label ?? "", alpha: alpha, popIn: followsClosely ? 1 : (time - event.time) / 0.15, in: context)
	}

	// Badges on the copied names stay until the end card.
	for event in copies {
		guard let rect = event.rect, let number = event.number else { continue }
		drawBadge(number, cell: rect, appeared: time - event.time, alpha: 1, in: context)
	}
	// Badges on the pasted cells hide while the picker is open on top of them.
	let pickerIsOpen = zip(pickerOpenings, pastes).contains { opening, paste in time >= opening && time < paste.time }
	for event in pastes where !pickerIsOpen {
		guard let rect = event.rect, let number = event.number else { continue }
		drawBadge(number, cell: rect, appeared: time - event.time, alpha: 1, in: context)
	}

	drawEndCard(progress: clamp((time - endCardStart) / endCardFade), elapsed: time - endCardStart, in: context)
}

// MARK: - Writing

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
	AVVideoCodecKey: AVVideoCodecType.proRes4444,
	AVVideoWidthKey: Int(size.width),
	AVVideoHeightKey: Int(size.height),
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
	kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
	kCVPixelBufferWidthKey as String: Int(size.width),
	kCVPixelBufferHeightKey as String: Int(size.height),
])
writer.add(input)
try? FileManager.default.removeItem(at: outputURL)
guard writer.startWriting() else {
	throw Failure(description: "Can't write \(outputURL.path): \(writer.error.map(String.init(describing:)) ?? "unknown error")")
}
writer.startSession(atSourceTime: .zero)

let frameCount = Int((duration * Double(frameRate)).rounded(.up))
for frame in 0..<frameCount {
	while !input.isReadyForMoreMediaData {
		Thread.sleep(forTimeInterval: 0.002)
	}
	var pixelBuffer: CVPixelBuffer?
	CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
	guard let pixelBuffer else {
		throw Failure(description: "Couldn't get a pixel buffer for frame \(frame).")
	}
	CVPixelBufferLockBaseAddress(pixelBuffer, [])
	let context = CGContext(
		data: CVPixelBufferGetBaseAddress(pixelBuffer),
		width: Int(size.width),
		height: Int(size.height),
		bitsPerComponent: 8,
		bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
		space: CGColorSpace(name: CGColorSpace.sRGB)!,
		bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
	)!
	context.clear(CGRect(origin: .zero, size: size))
	// Top-left origin, so the layout reads like the events' coordinates.
	context.translateBy(x: 0, y: size.height)
	context.scaleBy(x: 1, y: -1)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
	drawFrame(at: Double(frame) / Double(frameRate), in: context)
	NSGraphicsContext.restoreGraphicsState()
	CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
	adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate)))
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else {
	throw Failure(description: "Writing failed: \(writer.error.map(String.init(describing:)) ?? "unknown error")")
}
print(String(format: "Rendered %d frames (%.1f s) to %@", frameCount, duration, outputURL.path))
