import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PasteupCore

/// Writes clips to the clipboard and simulates ⌘V in the frontmost app.
enum Paster {
	/// Posting key events to other apps requires the Accessibility permission.
	static var isTrusted: Bool {
		AXIsProcessTrusted()
	}

	/// Shows the system prompt (and adds the app to the Accessibility list) if permission isn't granted yet.
	static func requestTrust() {
		// The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable C global.
		let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
	}

	static func openAccessibilitySettings() {
		let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
		NSWorkspace.shared.open(url)
	}

	static func write(_ items: [RawItem], to pasteboard: NSPasteboard) {
		let pasteboardItems = items.map { item in
			let pasteboardItem = NSPasteboardItem()
			for representation in item {
				pasteboardItem.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
			}
			return pasteboardItem
		}
		pasteboard.clearContents()
		pasteboard.writeObjects(pasteboardItems)
	}

	/// Uses the key code of the physical V key, which is correct for QWERTY, QWERTZ and AZERTY layouts.
	static func postCommandV() {
		let source = CGEventSource(stateID: .combinedSessionState)
		let keyCode = CGKeyCode(kVK_ANSI_V)
		let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
		let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
		keyDown?.flags = .maskCommand
		keyUp?.flags = .maskCommand
		keyDown?.post(tap: .cgSessionEventTap)
		keyUp?.post(tap: .cgSessionEventTap)
	}
}
