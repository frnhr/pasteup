-- Builds the two promo documents in Numbers, once:
--   Team.numbers: the "Availability" table to copy names from.
--   On-call rotation.numbers: the empty "Week 43" table to paste them into.
-- Numbers only finishes table edits while its window is visible, so each window moves on screen first.
-- Usage: osascript stage-numbers.applescript <output folder> <left> <top> <right> <bottom>
-- The bounds are global screen coordinates (origin at the top left of the main display).

on run argv
	set outputFolder to item 1 of argv
	set windowBounds to {(item 2 of argv) as integer, (item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer}

	set teamRows to {{"Name", "Team", "Status"}, ¬
		{"Ana Kovač", "Platform", "Available"}, ¬
		{"Marcus Lee", "Payments", "On leave"}, ¬
		{"Priya Nair", "Platform", "Available"}, ¬
		{"Tom Becker", "Mobile", "Available"}, ¬
		{"Lena Fischer", "Payments", "On leave"}, ¬
		{"Kenji Sato", "Data", "Available"}, ¬
		{"Omar Haddad", "Data", "On leave"}, ¬
		{"Sofia Rossi", "Mobile", "Available"}}
	set weekRows to {{"", "Mon", "Tue", "Wed", "Thu", "Fri"}, {"Primary", "", "", "", "", ""}}
	set gray to {36494, 36494, 37779}

	tell application "Numbers"
		activate
		close every document saving no

		set team to my newTable(windowBounds, "Team", "Availability", teamRows, 0)
		tell team
			set width of column 1 to 170
			set width of column 2 to 110
			set width of column 3 to 110
			repeat with rowIndex from 2 to count of teamRows
				if item 3 of item rowIndex of teamRows is "On leave" then set text color of row rowIndex to gray
			end repeat
		end tell
		-- Width and color changes select what they change; select A1 last so the document opens at the top left.
		tell team to set selection range to range "A1"
		save front document in (POSIX file (outputFolder & "/Team.numbers"))
		close front document saving no

		set week to my newTable(windowBounds, "Rotation", "Week 43", weekRows, 1)
		tell week
			set width of column 1 to 100
			repeat with columnIndex from 2 to 6
				set width of column columnIndex to 120
			end repeat
		end tell
		tell week to set selection range to range "A1"
		save front document in (POSIX file (outputFolder & "/On-call rotation.numbers"))
		close front document saving no
	end tell
end run

-- Creates a document with one table filled from `tableRows`, in a visible window, and returns the table.
on newTable(windowBounds, sheetName, tableName, tableRows, headerColumns)
	tell application "Numbers"
		set demo to make new document with properties {document template:template "Blank"}
		set bounds of front window to windowBounds
		delay 1
		tell active sheet of demo
			set name to sheetName
			delete every table
			set createdTable to make new table with properties {name:tableName, row count:(count of tableRows), column count:(count of item 1 of tableRows), header row count:1, header column count:headerColumns, footer row count:0}
		end tell
		repeat with rowIndex from 1 to count of tableRows
			set rowValues to item rowIndex of tableRows
			repeat with columnIndex from 1 to count of rowValues
				set value of cell columnIndex of row rowIndex of createdTable to item columnIndex of rowValues
			end repeat
		end repeat
		tell createdTable
			set font size of cell range to 16
			set height of every row to 34
			set position to {0, 30}
		end tell
		return createdTable
	end tell
end newTable
