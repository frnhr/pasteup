import AppKit

/// Modal alerts. The app is a menu-bar accessory, so it must activate itself for the alert to show in front.
enum Alerts {
	static func showError(_ message: String, error: Error) {
		NSApp.activate()
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = message
		alert.informativeText = String(describing: error)
		alert.runModal()
	}

	static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
		NSApp.activate()
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: confirmTitle).hasDestructiveAction = true
		alert.addButton(withTitle: "Cancel")
		return alert.runModal() == .alertFirstButtonReturn
	}

	static func showAccessibilityNeeded() {
		NSApp.activate()
		let alert = NSAlert()
		alert.messageText = "Pasteup needs the Accessibility permission to paste."
		alert.informativeText = """
			The clip is on the clipboard, so you can press ⌘V to paste it yourself.

			To let Pasteup paste for you, turn it on in System Settings → Privacy & Security → Accessibility.
			"""
		alert.addButton(withTitle: "Open System Settings")
		alert.addButton(withTitle: "Not Now")
		if alert.runModal() == .alertFirstButtonReturn {
			Paster.openAccessibilitySettings()
		}
	}
}
