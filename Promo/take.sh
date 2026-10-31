#!/bin/bash
# Records one promo take into build/promo (raw.mov and events.json).
#
# Pasteup gets a demo history (three older clips) and the default ⌃⌘V hotkey for the take; your history,
# hotkey and clipboard are restored afterwards, also when the take fails. Wispr Flow is quit during the take
# (its shortcut collides with ⌃⌘V) and relaunched afterwards. Fresh copies of the two Numbers documents
# are opened on the built-in display, and the pasted row is checked at the end.
# Don't touch the mouse or keyboard while it runs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
promo="$root/build/promo"
history="$HOME/Library/Application Support/Pasteup"
backup="$HOME/Library/Application Support/Pasteup.promo-backup"
domain=com.franhrzenjak.pasteup
hotkey=KeyboardShortcuts_showPicker

if [ -e "$backup" ]; then
	echo "take: $backup exists from an earlier take; restore it to $history first." >&2
	exit 1
fi

mkdir -p "$promo"
for tool in record clipboard; do
	if [ ! -x "$promo/$tool" ] || [ "$root/Promo/$tool.swift" -nt "$promo/$tool" ]; then
		swiftc -swift-version 5 -O "$root/Promo/$tool.swift" -o "$promo/$tool"
	fi
done
read -r -a layout <<< "$("$promo/record" layout)"
if [ ! -d "$promo/stage" ]; then
	mkdir -p "$promo/stage"
	osascript "$root/Promo/stage-numbers.applescript" "$promo/stage" "${layout[@]:8:4}"
fi

# Pasteup: demo history and default hotkey, restored on exit.
saved_hotkey="$(defaults read "$domain" "$hotkey" 2>/dev/null || true)"
wispr_was_running=false
if pgrep -x "Wispr Flow" >/dev/null; then
	wispr_was_running=true
fi
restore() {
	pkill -x Pasteup || true
	sleep 1
	rm -rf "$history"
	mv "$backup" "$history"
	if [ -n "$saved_hotkey" ]; then
		defaults write "$domain" "$hotkey" -string "$saved_hotkey"
	fi
	# Your clipboard as before the take, so the relaunched Pasteup sees its newest clip and records nothing.
	"$promo/clipboard" restore "$promo/clipboard.plist"
	rm -f "$promo/clipboard.plist"
	open -a /Applications/Pasteup.app
	echo "take: restored your Pasteup history and hotkey"
	if $wispr_was_running; then
		# By bundle ID: Wispr Flow bundles a helper app with the same name, which `open -a` would pick.
		open -b com.electron.wispr-flow
		echo "take: relaunched Wispr Flow"
	fi
}
"$promo/clipboard" save "$promo/clipboard.plist"
pkill -x Pasteup || true
sleep 1
mv "$history" "$backup"
trap restore EXIT
defaults delete "$domain" "$hotkey" 2>/dev/null || true

# Wispr Flow's "paste last transcript" shortcut is also ⌃⌘V: it would paste the last dictation into Numbers
# and then put the previous clipboard back, which Pasteup records as a new copy.
# It ignores the AppleScript quit command, so its main process gets SIGTERM, which quits it normally.
if $wispr_was_running; then
	pkill -TERM -f "^/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"
	for _ in $(seq 1 20); do
		pgrep -x "Wispr Flow" >/dev/null || break
		sleep 0.25
	done
	if pgrep -x "Wispr Flow" >/dev/null; then
		echo "take: Wispr Flow didn't quit" >&2
		exit 1
	fi
fi

# Waits until Pasteup has saved the given number of clips.
wait_for_clips() {
	for _ in $(seq 1 50); do
		if [ -f "$history/history.json" ] && [ "$(jq '.clips | length' "$history/history.json")" -ge "$1" ]; then
			return 0
		fi
		sleep 0.1
	done
	echo "take: Pasteup didn't record demo clip $1" >&2
	exit 1
}
# Pasteup captures the clipboard at launch, so the oldest demo clip goes there first.
printf '%s' "https://status.example.com/incidents/4821" | pbcopy
open -a /Applications/Pasteup.app
wait_for_clips 1
swift -swift-version 5 - <<'SWIFT'
import AppKit
NSPasteboard.general.clearContents()
NSPasteboard.general.writeObjects([NSColor(srgbRed: 0.27, green: 0.37, blue: 0.90, alpha: 1)])
Thread.sleep(forTimeInterval: 1)
SWIFT
wait_for_clips 2
printf '%s' "Standup moved to 9:30 tomorrow" | pbcopy
wait_for_clips 3
pkill -x Pasteup
sleep 1
now=$(date +%s)
jq --argjson now "$now" '
	def app(id; name): {bundleID: id, name: name};
	if (.clips | length) != 3 then error("expected 3 demo clips, found \(.clips | length)") else . end
	| .clips[0] |= (.capturedAt = ($now - 7300) | .sourceApp = app("com.apple.MobileSMS"; "Messages"))
	| .clips[1] |= (.capturedAt = ($now - 10900) | .sourceApp = app("com.apple.DigitalColorMeter"; "Digital Color Meter"))
	| .clips[2] |= (.capturedAt = ($now - 18100) | .sourceApp = app("com.apple.Safari"; "Safari"))
	| .stickyRow = 0
' "$history/history.json" > "$history/history.patched.json"
mv "$history/history.patched.json" "$history/history.json"
# The newest demo clip is on the clipboard, so the relaunch doesn't capture anything new.
printf '%s' "Standup moved to 9:30 tomorrow" | pbcopy
open -a /Applications/Pasteup.app
sleep 2

# Numbers: fresh copies of the documents, opened through Launch Services (Numbers is sandboxed).
if pgrep -x Numbers >/dev/null; then
	osascript -e 'tell application "Numbers" to close every document saving no'
fi
rm -rf "$promo/take"
ditto "$promo/stage" "$promo/take"
open -a Numbers "$promo/take/Team.numbers" "$promo/take/On-call rotation.numbers"
sleep 3
osascript "$root/Promo/stage-view.applescript" "${layout[@]:0:8}" >/dev/null

"$promo/record" take "$promo"

pasted="$(osascript -e 'tell application "Numbers" to tell table "Week 43" of active sheet of (first document whose name starts with "On-call") to get value of cells 2 thru 6 of row 2')"
expected="Ana Kovač, Priya Nair, Tom Becker, Kenji Sato, Sofia Rossi"
if [ "$pasted" != "$expected" ]; then
	echo "take: the pasted row is \"$pasted\", expected \"$expected\"" >&2
	exit 1
fi
echo "take: OK, pasted $pasted"
