import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
	let controller: AppController

	@State private var launchAtLogin = SMAppService.mainApp.status == .enabled
	@State private var launchAtLoginNote: String?
	@State private var isTrusted = Paster.isTrusted

	var body: some View {
		Form {
			Section {
				KeyboardShortcuts.Recorder("Show clips:", name: .showPicker)
				LabeledContent("History size:") {
					HStack {
						TextField("History size", value: capacity, format: .number)
							.labelsHidden()
							.frame(width: 60)
							.multilineTextAlignment(.trailing)
						Stepper("History size", value: capacity, in: AppController.capacityRange)
							.labelsHidden()
						Text("clips")
					}
				}
			}
			Section {
				// A closure, not a method reference: passing `updateLaunchAtLogin` directly crashes swiftc 6.3.1 in IRGen.
				Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { updateLaunchAtLogin($0) }))
				if let launchAtLoginNote {
					Text(launchAtLoginNote)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Section {
				LabeledContent("Accessibility:") {
					if isTrusted {
						Label("Granted", systemImage: "checkmark.circle.fill")
							.foregroundStyle(.green)
					} else {
						Button("Open System Settings…") {
							Paster.openAccessibilitySettings()
						}
					}
				}
				Text("Needed to paste into other apps. Without it, the chosen clip is only put on the clipboard.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.frame(width: 460)
		.fixedSize()
		.onAppear {
			isTrusted = Paster.isTrusted
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			isTrusted = Paster.isTrusted
		}
	}

	private var capacity: Binding<Int> {
		Binding(
			get: { controller.capacity },
			set: { controller.setCapacity($0) }
		)
	}

	private func updateLaunchAtLogin(_ enabled: Bool) {
		let service = SMAppService.mainApp
		do {
			if enabled {
				try service.register()
			} else {
				try service.unregister()
			}
			launchAtLoginNote = service.status == .requiresApproval
				? "Approve Pasteup in System Settings → General → Login Items."
				: nil
		} catch {
			launchAtLoginNote = "Couldn't change the login item: \(error.localizedDescription)"
		}
		launchAtLogin = service.status == .enabled
	}
}
