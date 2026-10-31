-- Sets up the two promo windows for a take: bounds, no toolbar or inspector, actual size.
-- Open the documents first with `open -a Numbers`: Numbers is sandboxed and can't open files
-- on other volumes through AppleScript.
-- Usage: osascript stage-view.applescript <team bounds: left top right bottom> <on-call bounds: left top right bottom>
-- The bounds are global screen coordinates (origin at the top left of the main display).

on run argv
	set teamBounds to my boundsFrom(argv, 1)
	set onCallBounds to my boundsFrom(argv, 5)
	my setUpWindow("On-call rotation", onCallBounds)
	my setUpWindow("Team", teamBounds)
end run

on boundsFrom(argv, firstIndex)
	set values to {}
	repeat with step from 0 to 3
		set end of values to (item (firstIndex + step) of argv) as integer
	end repeat
	return values
end boundsFrom

-- The View menu acts on the key window. Reordering windows through Numbers doesn't make one key,
-- raising it through Accessibility does.
on setUpWindow(documentName, windowBounds)
	tell application "Numbers"
		activate
		set bounds of (first window whose name starts with documentName) to windowBounds
	end tell
	tell application "System Events" to tell process "Numbers"
		set frontmost to true
		perform action "AXRaise" of (first window whose name starts with documentName)
	end tell
	delay 0.6
	-- Menu item titles only update for the new front window while the menu is open.
	tell application "System Events" to tell process "Numbers"
		set viewMenu to menu "View" of menu bar item "View" of menu bar 1
		click menu bar item "View" of menu bar 1
		set toolbarHidden to not (exists menu item "Hide Toolbar" of viewMenu)
		set inspectorHidden to not (exists menu item "Hide Inspector" of menu 1 of menu item "Inspector" of viewMenu)
		key code 53
		if not toolbarHidden then click menu item "Hide Toolbar" of viewMenu
		if not inspectorHidden then click menu item "Hide Inspector" of menu 1 of menu item "Inspector" of viewMenu
		click menu item "Actual Size" of menu 1 of menu item "Zoom" of viewMenu
	end tell
end setUpWindow
