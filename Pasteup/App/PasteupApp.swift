import AppKit
import SwiftUI

@main
struct PasteupApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	var body: some Scene {
		MenuBarExtra("Pasteup", image: "MenuBarIcon") {
			MenuBarMenu(controller: appDelegate.controller)
		}
		Settings {
			SettingsView(controller: appDelegate.controller)
		}
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	let controller = AppController()

	func applicationDidFinishLaunching(_ notification: Notification) {
		controller.start()
	}
}

private struct MenuBarMenu: View {
	let controller: AppController
	@Environment(\.openSettings) private var openSettings

	var body: some View {
		Button("Show Clips") {
			controller.showPicker()
		}
		Divider()
		Button("Settings…") {
			NSApp.activate()
			openSettings()
		}
		.keyboardShortcut(",")
		Button("Clear History…") {
			controller.confirmClearHistory()
		}
		.disabled(controller.history.clips.isEmpty)
		Divider()
		Button("About Pasteup") {
			AboutPanel.show()
		}
		Button("Quit Pasteup") {
			NSApp.terminate(nil)
		}
		.keyboardShortcut("q")
	}
}
