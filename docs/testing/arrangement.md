# Clip arrangement checks

Automated: `make test` covers ID-based moves in both directions and to the end, concurrent arrivals, missing source/destination IDs, remembered-row and paste behavior, Saved membership, and 1,000-row index round trips. `make build` compiles the AppKit/SwiftUI integration. `Scripts/test-picker-arrangement.sh` renders a disposable SwiftUI fixture and exercises the production gesture controller: each visible destination, scrolled rows, translated window coordinates, returning inside, interior non-list drops, filtering, cancellation and outside deletion. It briefly opens a fixture window and never touches the real clipboard or clip stores.

The following are manual acceptance checks; they are not implied by passing the core tests. Use disposable clips in both History and Saved.

- Move a clip into or out of first position in each list: paste into a disposable document to confirm the clipboard now contains the new first clip, with no new History entry. Move clips below first position and confirm the clipboard stays unchanged. Delete the first clip and confirm it updates; deleting the last clip clears the clipboard.
- Drag a row upward, downward and to the end. The insertion line should identify the destination; release should select the moved clip. Close/reopen, then quit/relaunch without changing the clipboard: order and remembered selection should remain. Paste the selected clip and verify the existing paste-to-top/remembered-position behavior.
- Fill a list beyond the viewport. Hold the drag near each edge without moving the mouse; scrolling should continue, exposing further destinations. Repeat with a long Saved list.
- Drag outside each picker edge. Before release, a red trash badge with “Release to delete” should follow the pointer. Move across displays, including a display above or left of the main display; the badge should remain visible on the pointer's screen.
- Return inside after showing the trash badge: it should revert to arrangement feedback. Release on the search field, tabs, footer or empty interior space: no deletion or reorder should occur.
- Release outside: History deletes only its copy; Saved unsaves only its copy. Test with matching content present in both lists.
- Press Escape both inside and outside during a drag, then release: neither order nor membership should change. Close the picker through its hotkey during a drag: reopening should also show no mutation. Change focus during a held drag: the picker and feedback should remain; focus loss alone must never delete.
- Filter the list: the clear-filter hint should appear, reordering should be disabled, and drag-out deletion should still address the correct filtered clip.
- Make a new clipboard copy during a drag: the source and destination must still be resolved by ID. If the source is evicted, the gesture should cancel. Verify no accidental paste or bookmark action on release after dragging.
- On disposable storage, provoke an index write failure: show an error, restore the original list, and retain the clip's blobs. Retry after restoring write access.

The gesture never exports a pasteboard item to another application. Changes occur only on a tracked mouse release, never from pointer position or loss of focus alone. An unchanged clipboard fingerprint is remembered independently of row order to avoid a duplicate startup capture after arrangement.
