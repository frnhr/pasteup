<p align="center">
  <img src="docs/icon.png" width="128" alt="Pasteup icon">
</p>

<h1 align="center">Pasteup</h1>

<p align="center">
  A small macOS clipboard manager built for serial copy-paste:<br>
  copy several things, then paste them back one by one, in the order you copied them.
</p>

<p align="center"><b>Coded 100% by Claude.</b></p>

<p align="center">
  <img src="docs/demo.gif" width="800" alt="Five names are copied one by one from a Numbers table, skipping people on leave, then pasted in the same order into Monday to Friday of another table with Control-Command-V and Return">
</p>

## Serial paste

Say you need to move a name, an email address, a phone number and a street address from an email into a form. Copy all four, one after another. Then, in the form:

1. Press ⌃⌘V. Pasteup shows your recent clips, newest on top. Move down to the name (row 4) and press ↩. Pasteup pastes it and moves it to the top.
2. Press ⌃⌘V again. Pasteup remembers that you pasted from row 4 and highlights row 4 again, which now holds the email address. Press ↩.
3. Do the same for the phone number and the address.

After the first paste, every next clip is just ⌃⌘V, ↩. As soon as you copy something new, the picker goes back to highlighting the newest clip at the top.

The screenshot below shows this after two pastes: the name and the email address are on top, and the phone number is highlighted as the next one up.

<p align="center">
  <img src="docs/picker.png" width="560" alt="The Pasteup picker, with the fourth row highlighted">
</p>

## Features

- **Menu bar only.** No Dock icon. The picker opens in the middle of the active screen, and the paste goes to the app you were working in.
- **Keyboard first.** ↑ ↓ to move, ↩ to paste, ⇧↩ to paste as plain text, ⌘S to save or unsave a clip, ⌘⌫ to delete a clip, ← → to switch between History and Saved, type to filter, esc to clear the filter or close. Double-clicking a row also pastes.
- **Saved clips.** Click the bookmark on a clip (it shows when you point at the row or select it), or press ⌘S, to keep a copy in the Saved list. Saved clips stay until you unsave them: the history size, deleting and Clear History don't touch them. Each clip is saved only once, and a clip in the history shows a filled bookmark when the same content is saved. Pasting from Saved follows the same remembered-row rule as the history. The picker always opens on History.
- **Arrange either list.** Drag a row to the insertion line to reorder it; pause near the top or bottom of the list to scroll. Order is saved across restarts, and the moved clip stays selected and becomes the remembered row. If arranging or deleting changes the first clip in either list, the clipboard updates to that clip without pasting; removing the last clip clears it. Pasting still moves a clip to the top and remembers its former row. Drag outside the picker until the red “Release to delete” badge appears, then release to delete from History or unsave from Saved; the other list’s copy stays intact. Return inside to cancel deletion, or press Escape to cancel the entire drag. The search field, tabs and footer are inside the picker and never count as deletion targets. While filtering, clear the filter to reorder; dragging outside to delete still works.
- **Text, rich text, images, files and colors.** Every format of a copied item is kept, so the app you paste into gets the same choices it would get from the original copy. Rows show a short preview: the text, an image thumbnail, file names or a color swatch, plus the app it was copied from.
- **History that survives restarts.** Clips are stored in `~/Library/Application Support/Pasteup`. The history keeps 50 clips by default (1 to 1000 in Settings). Copying the same thing again within 2 seconds doesn't add a duplicate; otherwise duplicates are kept, because the order matters.
- **Respects password managers.** Items marked as concealed or transient (the [nspasteboard.org](http://nspasteboard.org) convention, used by 1Password and others) are not recorded.
- **Nothing leaves your Mac.** No network access, no analytics.

## Settings

<img src="docs/settings.png" width="460" alt="Pasteup settings: hotkey, history size, launch at login, Accessibility">

You can change the hotkey, the history size and launch at login.

To paste, Pasteup puts the clip on the clipboard and presses ⌘V for you. macOS only allows that with the Accessibility permission (System Settings → Privacy & Security → Accessibility). Without it, Pasteup still moves the clip to the top and puts it on the clipboard, and you press ⌘V yourself.

## Building

There's no prebuilt release yet. Pasteup needs macOS 14 or later (it's developed on macOS 26). To build it you need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
make run    # builds a Release version, copies it to /Applications/Pasteup.app and opens it
```

Other targets: `make test` runs the tests of the core logic, `make build` makes a Debug build, and `make icons` redraws the app icon and the menu bar icon (see `Scripts/render-icons.swift`).

To bump the version, use `make bump-patch`, `make bump-minor`, or `make bump-major`. These require Python 3 and XcodeGen. Each target updates the version in `project.yml`, resets lower version components to zero, increments the build number, moves `CHANGELOG.md`’s Unreleased entries into a new dated version section (leaving Unreleased empty), regenerates the Xcode project and `Pasteup/Info.plist`, and prints the old and new versions. For example, from `0.2.0`, the targets produce `0.2.1`, `0.3.0`, and `1.0.0`, respectively. If generation fails, the script restores the spec, plist, and changelog. Building/installing (`make run`), committing, and tagging remain separate steps.

The build is ad-hoc signed by default. macOS ties the Accessibility permission to the app's signature, so with ad-hoc signing you have to grant it again after every rebuild. To avoid that, sign with your Apple ID (a free one works): copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your team ID in it.

## Project layout

- `Packages/PasteupCore`: the history rules (the remembered row, duplicates, history size), the saved clips and the picker state, as a plain Swift package with tests.
- `Pasteup`: the app: clipboard monitoring, storage, the picker panel and the settings, in SwiftUI and AppKit.
- `project.yml`: the XcodeGen spec. The Xcode project is generated from it and isn't checked in.
- `Promo`: scripts that record the promo video with real input in Numbers and render it (`make promo-take`, then `make promo-render`).

## Credits

Coded 100% by Claude (Anthropic), in Claude Code. Idea, direction and testing by [Fran Hrženjak](https://changeset.hr). The hotkey uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus.

## License

MIT, see [LICENSE](LICENSE). The license doesn't cover the Pasteup name and icon. If you publish your own build or a fork, please give it a different name and icon.
