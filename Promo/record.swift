// Records one take of the Pasteup promo on the built-in display.
//
//   record layout          Prints window bounds: the Team and On-call windows for stage-view.applescript,
//                          then a wider window for building the documents with stage-numbers.applescript.
//   record probe <folder>  Finds the tables without any input and saves the window captures it read.
//   record take <folder>   Covers the display with a backdrop, finds the tables, then records the area with
//                          ScreenCaptureKit while playing the storyboard with real mouse and keyboard events.
//                          Writes raw.mov and events.json into the folder.
//
// Needs the Screen Recording and Accessibility permissions (granted to the terminal it runs from),
// Numbers with Team.numbers and On-call rotation.numbers open, and Pasteup running with the ⌃⌘V hotkey.
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

struct Failure: Error, CustomStringConvertible {
	let description: String

	init(_ description: String) {
		self.description = description
	}
}

// MARK: - Layout

/// The recorded area is 1440 × 810 pt of the built-in display. Recorded at 2×, it scales to exactly 1920 × 1080.
/// All rects use global screen coordinates (origin at the top left of the main display) unless noted.
struct Layout {
	static let regionSize = CGSize(width: 1440, height: 810)

	let displayID: CGDirectDisplayID
	let display: CGRect
	let region: CGRect

	init() throws {
		var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
		var displayCount: UInt32 = 0
		CGGetActiveDisplayList(16, &displayIDs, &displayCount)
		guard let builtIn = displayIDs.prefix(Int(displayCount)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
			throw Failure("No built-in display is active.")
		}
		displayID = builtIn
		display = CGDisplayBounds(builtIn)
		guard display.width == Self.regionSize.width, display.height >= Self.regionSize.height else {
			throw Failure("The built-in display is \(display.size) pt; the layout needs it 1440 pt wide and at least 810 pt tall.")
		}
		region = CGRect(
			x: display.minX,
			y: display.minY + (display.height - Self.regionSize.height) / 2,
			width: Self.regionSize.width,
			height: Self.regionSize.height
		)
	}

	var teamWindow: CGRect { global(CGRect(x: 75, y: 145, width: 470, height: 520)) }
	var onCallWindow: CGRect { global(CGRect(x: 585, y: 270, width: 780, height: 270)) }
	/// Wide enough that Numbers never scrolls while building the documents, even with its inspector open.
	var buildWindow: CGRect { global(CGRect(x: 60, y: 60, width: 1320, height: 640)) }
	/// Where the pointer waits while the picker is in use: below the picker, left of the keycap overlays.
	var restPoint: CGPoint { global(CGPoint(x: 560, y: 712)) }

	func global(_ rect: CGRect) -> CGRect {
		rect.offsetBy(dx: region.minX, dy: region.minY)
	}

	func global(_ point: CGPoint) -> CGPoint {
		CGPoint(x: point.x + region.minX, y: point.y + region.minY)
	}

	func local(_ rect: CGRect) -> CGRect {
		rect.offsetBy(dx: -region.minX, dy: -region.minY)
	}

	/// The display-local rect that ScreenCaptureKit records.
	var sourceRect: CGRect {
		region.offsetBy(dx: -display.minX, dy: -display.minY)
	}
}

// MARK: - Input

/// Real mouse and keyboard events, posted where the hardware's would be.
enum Input {
	static let source = CGEventSource(stateID: .hidSystemState)

	static var pointer: CGPoint {
		CGEvent(source: nil)?.location ?? .zero
	}

	/// Moves the pointer along an eased, slightly curved path, like a hand would.
	static func move(to target: CGPoint, duration: Double) async {
		let start = pointer
		let distance = hypot(target.x - start.x, target.y - start.y)
		let normal = distance > 0 ? CGPoint(x: -(target.y - start.y) / distance, y: (target.x - start.x) / distance) : .zero
		let arc = min(36, distance * 0.07)
		let steps = max(1, Int(duration * 120))
		for step in 1...steps {
			let progress = Double(step) / Double(steps)
			let eased = progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(-2 * progress + 2, 3) / 2
			let bulge = sin(progress * .pi) * arc
			let point = CGPoint(
				x: start.x + (target.x - start.x) * eased + normal.x * bulge,
				y: start.y + (target.y - start.y) * eased + normal.y * bulge
			)
			CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
				.post(tap: .cghidEventTap)
			try? await Task.sleep(for: .seconds(duration / Double(steps)))
		}
	}

	static func click(at point: CGPoint) async {
		for type in [CGEventType.leftMouseDown, .leftMouseUp] {
			let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
			event?.setIntegerValueField(.mouseEventClickState, value: 1)
			event?.post(tap: .cghidEventTap)
			try? await Task.sleep(for: .milliseconds(70))
		}
	}

	/// Presses a key with modifiers, holding the modifier keys down around it like a person does.
	static func press(_ keyCode: Int, modifiers: [(keyCode: Int, flag: CGEventFlags)] = []) async {
		var flags: CGEventFlags = []
		for modifier in modifiers {
			flags.insert(modifier.flag)
			post(modifier.keyCode, down: true, flags: flags)
		}
		post(keyCode, down: true, flags: flags)
		try? await Task.sleep(for: .milliseconds(50))
		post(keyCode, down: false, flags: flags)
		for modifier in modifiers.reversed() {
			flags.remove(modifier.flag)
			post(modifier.keyCode, down: false, flags: flags)
		}
		try? await Task.sleep(for: .milliseconds(30))
	}

	static func scroll(at point: CGPoint, vertical: Int32, horizontal: Int32) {
		CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
			.post(tap: .cghidEventTap)
		let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)
		event?.post(tap: .cghidEventTap)
	}

	private static func post(_ keyCode: Int, down: Bool, flags: CGEventFlags) {
		let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
		event?.flags = flags
		event?.post(tap: .cghidEventTap)
	}

	static let command = (keyCode: kVK_Command, flag: CGEventFlags.maskCommand)
	static let control = (keyCode: kVK_Control, flag: CGEventFlags.maskControl)
}

func pause(_ seconds: Double) async {
	try? await Task.sleep(for: .seconds(seconds))
}

// MARK: - Windows and tables

struct WindowInfo {
	let id: CGWindowID
	let frame: CGRect
}

func onScreenWindows(owner: String) -> [[String: Any]] {
	let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
	return windows.filter { $0[kCGWindowOwnerName as String] as? String == owner }
}

func numbersWindow(titled prefix: String) throws -> WindowInfo {
	for window in onScreenWindows(owner: "Numbers") where (window[kCGWindowName as String] as? String ?? "").hasPrefix(prefix) {
		let bounds = window[kCGWindowBounds as String] as! CFDictionary
		return WindowInfo(id: window[kCGWindowNumber as String] as! CGWindowID, frame: CGRect(dictionaryRepresentation: bounds)!)
	}
	throw Failure("No on-screen Numbers window titled \(prefix)….")
}

var pickerIsOpen: Bool {
	onScreenWindows(owner: "Pasteup").contains { $0[kCGWindowLayer as String] as? Int == 3 }
}

func waitForPicker(open: Bool) async throws {
	for _ in 0..<75 where pickerIsOpen != open {
		await pause(0.02)
	}
	guard pickerIsOpen == open else {
		throw Failure("The Pasteup picker didn't \(open ? "open" : "close") within 1.5 s.")
	}
}

struct TableGeometry {
	/// Top left corner of the first cell.
	let origin: CGPoint
	let columnWidths: [CGFloat]
	let rowHeight: CGFloat

	func cell(row: Int, column: Int) -> CGRect {
		CGRect(
			x: origin.x + columnWidths.prefix(column).reduce(0, +),
			y: origin.y + CGFloat(row) * rowHeight,
			width: columnWidths[column],
			height: rowHeight
		)
	}
}

/// Captures a window at 2× without the pointer.
func capture(_ window: WindowInfo) async throws -> CGImage {
	let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
	guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
		throw Failure("ScreenCaptureKit can't see window \(window.id).")
	}
	let configuration = SCStreamConfiguration()
	configuration.width = Int(window.frame.width * 2)
	configuration.height = Int(window.frame.height * 2)
	configuration.showsCursor = false
	return try await SCScreenshotManager.captureImage(
		contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
		configuration: configuration
	)
}

/// Finds a table by its header row, the only large area with the header fill: about 190, 192, 191 once the
/// Display P3 capture is drawn into an sRGB context (Numbers' gray is 201, 203, 202 in sRGB per NSColor).
/// Numbers doesn't expose table cells through Accessibility, so this reads the window's pixels.
/// Only long horizontal runs of the fill count: antialiased text has pixels of the same gray, but in short runs.
func findTable(in window: WindowInfo, image: CGImage, columnWidths: [CGFloat], rowHeight: CGFloat) throws -> TableGeometry {
	let width = image.width
	let height = image.height
	let context = CGContext(
		data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
		space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	)!
	context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
	let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
	let scale = CGFloat(width) / window.frame.width
	let minimumRun = Int(16 * scale)

	func isHeaderFill(_ offset: Int) -> Bool {
		abs(Int(pixels[offset]) - 190) <= 8 && abs(Int(pixels[offset + 1]) - 192) <= 8 && abs(Int(pixels[offset + 2]) - 191) <= 8
			&& abs(Int(pixels[offset]) - Int(pixels[offset + 2])) <= 4
	}

	// Skip the title and tab bars at the top and the scroll bars at the edges.
	let edge = Int(24 * scale)
	var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
	for row in Int(60 * scale)..<(height - edge) {
		var runStart = -1
		for column in edge...(width - edge) {
			let matches = column < width - edge && isHeaderFill((row * width + column) * 4)
			if matches, runStart < 0 {
				runStart = column
			} else if !matches, runStart >= 0 {
				if column - runStart >= minimumRun {
					minX = min(minX, runStart)
					maxX = max(maxX, column - 1)
					minY = min(minY, row)
					maxY = max(maxY, row)
				}
				runStart = -1
			}
		}
	}
	guard minX <= maxX else {
		throw Failure("No table header found in window \(window.id).")
	}
	let header = CGRect(
		x: window.frame.minX + CGFloat(minX) / scale,
		y: window.frame.minY + CGFloat(minY) / scale,
		width: CGFloat(maxX - minX + 1) / scale,
		height: CGFloat(maxY - minY + 1) / scale
	)
	let expectedWidth = columnWidths.reduce(0, +)
	guard abs(header.width - expectedWidth) <= 4, abs(header.height - rowHeight) <= 4 else {
		throw Failure("The header found in window \(window.id) is \(header.size); expected \(expectedWidth) × \(rowHeight).")
	}
	return TableGeometry(origin: header.origin, columnWidths: columnWidths, rowHeight: rowHeight)
}

let teamColumns: [CGFloat] = [170, 110, 110]
let onCallColumns: [CGFloat] = [100, 120, 120, 120, 120, 120]

/// Raises a window, clears its selection and scrolls it to the top left, so the take starts from a clean view.
func prepare(_ window: WindowInfo) async {
	await Input.move(to: CGPoint(x: window.frame.midX, y: window.frame.minY + 14), duration: 0.2)
	await Input.click(at: Input.pointer)
	await pause(0.2)
	await Input.press(kVK_Escape)
	await Input.press(kVK_Escape)
	for _ in 0..<6 {
		Input.scroll(at: CGPoint(x: window.frame.midX, y: window.frame.midY), vertical: 400, horizontal: 0)
		await pause(0.03)
	}
}

// MARK: - Recording

/// Records an area of a display to a movie file with ScreenCaptureKit.
final class Recorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
	private var stream: SCStream?
	private var started: CheckedContinuation<Void, Error>?
	private var finished: CheckedContinuation<Void, Error>?
	/// When the first frame was recorded, on the `CACurrentMediaTime` clock.
	private(set) var startTime: Double = 0

	func start(displayID: CGDirectDisplayID, sourceRect: CGRect, to url: URL) async throws {
		let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
			throw Failure("ScreenCaptureKit can't see display \(displayID).")
		}
		let configuration = SCStreamConfiguration()
		configuration.sourceRect = sourceRect
		configuration.width = Int(sourceRect.width * 2)
		configuration.height = Int(sourceRect.height * 2)
		configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
		configuration.showsCursor = true
		configuration.showMouseClicks = true
		configuration.queueDepth = 8
		let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: nil)

		let outputConfiguration = SCRecordingOutputConfiguration()
		outputConfiguration.outputURL = url
		outputConfiguration.outputFileType = .mov
		outputConfiguration.videoCodecType = .hevc
		try stream.addRecordingOutput(SCRecordingOutput(configuration: outputConfiguration, delegate: self))
		self.stream = stream

		try await withCheckedThrowingContinuation { continuation in
			started = continuation
			stream.startCapture { error in
				if let error {
					DispatchQueue.main.async { self.resumeStarted(throwing: error) }
				}
			}
		}
	}

	func stop() async throws {
		try await withCheckedThrowingContinuation { continuation in
			finished = continuation
			stream?.stopCapture { error in
				if let error {
					DispatchQueue.main.async { self.resumeFinished(throwing: error) }
				}
			}
		}
	}

	func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
		let time = CACurrentMediaTime()
		DispatchQueue.main.async {
			self.startTime = time
			self.resumeStarted(throwing: nil)
		}
	}

	func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
		DispatchQueue.main.async { self.resumeFinished(throwing: nil) }
	}

	func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
		DispatchQueue.main.async {
			self.resumeStarted(throwing: error)
			self.resumeFinished(throwing: error)
		}
	}

	private func resumeStarted(throwing error: Error?) {
		guard let started else { return }
		self.started = nil
		if let error { started.resume(throwing: error) } else { started.resume() }
	}

	private func resumeFinished(throwing error: Error?) {
		guard let finished else { return }
		self.finished = nil
		if let error { finished.resume(throwing: error) } else { finished.resume() }
	}
}

// MARK: - Events

/// What happened when, for the overlays. Times are seconds since the first recorded frame,
/// rects are in points relative to the recorded area.
struct Event: Codable {
	enum Kind: String, Codable {
		case keys, copy, paste, done
	}

	let time: Double
	let kind: Kind
	var label: String?
	var number: Int?
	var rect: CGRect?
}

struct TakeLog: Codable {
	let regionSize: CGSize
	var events: [Event] = []
}

// MARK: - Backdrop

/// A plain gradient behind the two windows, covering whatever else is on the display.
final class BackdropView: NSView {
	override func draw(_ dirtyRect: NSRect) {
		let gradient = NSGradient(
			starting: NSColor(srgbRed: 0.95, green: 0.96, blue: 0.99, alpha: 1),
			ending: NSColor(srgbRed: 0.83, green: 0.87, blue: 0.97, alpha: 1)
		)!
		gradient.draw(in: bounds, angle: -90)
	}
}

@MainActor
func showBackdrop(displayID: CGDirectDisplayID) throws -> NSWindow {
	guard let screen = NSScreen.screens.first(where: {
		($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
	}) else {
		throw Failure("No NSScreen for display \(displayID).")
	}
	let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
	window.contentView = BackdropView()
	window.ignoresMouseEvents = true
	window.isReleasedWhenClosed = false
	window.setFrame(screen.frame, display: true)
	window.orderFrontRegardless()
	return window
}

// MARK: - Take

/// Data rows (1-based, after the header) of the available people, copied in this order: Ana, Priya, Tom, Kenji, Sofia.
let copiedRows = [1, 3, 4, 6, 8]

/// Clicks toward the right end of a cell, so the pointer doesn't cover the name.
func clickPoint(_ cell: CGRect) -> CGPoint {
	CGPoint(x: cell.maxX - 26, y: cell.midY + 3)
}

@MainActor
func recordTake(into folder: URL) async throws {
	let layout = try Layout()
	let backdrop = try showBackdrop(displayID: layout.displayID)
	defer { backdrop.orderOut(nil) }

	guard let numbers = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iWork.Numbers").first else {
		throw Failure("Numbers isn't running.")
	}
	numbers.activate()
	await pause(0.8)
	let onCallWindow = try numbersWindow(titled: "On-call rotation")
	let teamWindow = try numbersWindow(titled: "Team")
	await prepare(onCallWindow)
	await prepare(teamWindow)
	await Input.move(to: layout.restPoint, duration: 0.3)
	// Let the scroll bars fade out before reading the window pixels.
	await pause(1.6)
	let team = try findTable(in: teamWindow, image: try await capture(teamWindow), columnWidths: teamColumns, rowHeight: 34)
	let onCall = try findTable(in: onCallWindow, image: try await capture(onCallWindow), columnWidths: onCallColumns, rowHeight: 34)
	guard !pickerIsOpen else {
		throw Failure("The Pasteup picker is already open.")
	}

	let recorder = Recorder()
	try await recorder.start(displayID: layout.displayID, sourceRect: layout.sourceRect, to: folder.appending(path: "raw.mov"))
	var log = TakeLog(regionSize: Layout.regionSize)
	func record(_ kind: Event.Kind, label: String? = nil, number: Int? = nil, rect: CGRect? = nil) {
		log.events.append(Event(time: CACurrentMediaTime() - recorder.startTime, kind: kind, label: label, number: number, rect: rect.map(layout.local)))
	}

	do {
		await pause(1.0)
		for (index, row) in copiedRows.enumerated() {
			let cell = team.cell(row: row, column: 0)
			await Input.move(to: clickPoint(cell), duration: index == 0 ? 0.6 : 0.45)
			await pause(0.1)
			await Input.click(at: clickPoint(cell))
			await pause(0.18)
			record(.keys, label: "⌘C")
			await Input.press(kVK_ANSI_C, modifiers: [Input.command])
			record(.copy, number: index + 1, rect: cell)
			await pause(0.42)
		}

		let monday = onCall.cell(row: 1, column: 1)
		await Input.move(to: clickPoint(monday), duration: 0.7)
		await pause(0.1)
		// The first click only brings the window forward; Numbers selects the cell on the second one,
		// which comes after the double-click interval (0.5 s) so it doesn't start editing the cell.
		await Input.click(at: clickPoint(monday))
		await pause(0.62)
		await Input.click(at: clickPoint(monday))
		await pause(0.2)
		await Input.move(to: layout.restPoint, duration: 0.35)
		await pause(0.25)

		for day in 1...5 {
			if day > 1 {
				record(.keys, label: "⇥")
				await Input.press(kVK_Tab)
				await pause(0.32)
			}
			record(.keys, label: "⌃⌘V")
			await Input.press(kVK_ANSI_V, modifiers: [Input.control, Input.command])
			try await waitForPicker(open: true)
			await pause(day == 1 ? 0.5 : 0.4)
			if day == 1 {
				// The first copy is the 5th row; after that the picker opens on the 5th row by itself.
				for count in 1...4 {
					record(.keys, label: Array(repeating: "↓", count: count).joined(separator: " "))
					await Input.press(kVK_DownArrow)
					await pause(0.2)
				}
				await pause(0.25)
			}
			record(.keys, label: "↩")
			await Input.press(kVK_Return)
			try await waitForPicker(open: false)
			record(.paste, number: day, rect: onCall.cell(row: 1, column: day))
			await pause(0.45)
		}
		await pause(1.3)
		record(.done)
	} catch {
		try? await recorder.stop()
		throw error
	}
	try await recorder.stop()

	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	try encoder.encode(log).write(to: folder.appending(path: "events.json"))
	print("Recorded \(String(format: "%.1f", log.events.last?.time ?? 0)) s into \(folder.path)")
}

/// Finds both tables without any input and saves the captures, for checking the detection.
func probe(into folder: URL) async throws {
	for (title, columns) in [("Team", teamColumns), ("On-call rotation", onCallColumns)] {
		let window = try numbersWindow(titled: title)
		let image = try await capture(window)
		let url = folder.appending(path: "probe-\(title).png")
		let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
		CGImageDestinationAddImage(destination, image, nil)
		CGImageDestinationFinalize(destination)
		do {
			let table = try findTable(in: window, image: image, columnWidths: columns, rowHeight: 34)
			let origin = CGPoint(x: table.origin.x - window.frame.minX, y: table.origin.y - window.frame.minY)
			print("\(title): table at \(origin) in the window, capture saved to \(url.path)")
		} catch {
			print("\(title): \(error), capture saved to \(url.path)")
		}
	}
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "layout":
	do {
		let layout = try Layout()
		let bounds = [layout.teamWindow, layout.onCallWindow, layout.buildWindow].flatMap { [$0.minX, $0.minY, $0.maxX, $0.maxY].map { String(Int($0)) } }
		print(bounds.joined(separator: " "))
	} catch {
		FileHandle.standardError.write(Data("record: \(error)\n".utf8))
		exit(1)
	}
case "take", "probe":
	guard let path = arguments.dropFirst().first else {
		FileHandle.standardError.write(Data("usage: record \(arguments.first!) <folder>\n".utf8))
		exit(2)
	}
	let isTake = arguments.first == "take"
	let app = NSApplication.shared
	app.setActivationPolicy(.accessory)
	Task { @MainActor in
		do {
			let folder = URL(filePath: path, directoryHint: .isDirectory)
			if isTake {
				try await recordTake(into: folder)
			} else {
				try await probe(into: folder)
			}
			exit(0)
		} catch {
			FileHandle.standardError.write(Data("record: \(error)\n".utf8))
			exit(1)
		}
	}
	app.run()
default:
	FileHandle.standardError.write(Data("usage: record layout | record probe <folder> | record take <folder>\n".utf8))
	exit(2)
}
