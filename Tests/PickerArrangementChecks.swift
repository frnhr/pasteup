// Compiled with the production PickerArrangement.swift by Scripts/test-picker-arrangement.sh.
// Only its controller/model dependencies are stand-ins; geometry and gesture handling are real.
import AppKit
import SwiftUI
import PasteupCore

final class PickerPanel: NSPanel {}
final class PickerModel {
 var geometry = PickerGeometry()
 var draggedID: Clip.ID?
 var insertionID: Clip.ID?
 var insertionAtEnd = false
 var clips: [Clip]
 var state: PickerState
 var moves: [(Clip.ID, Clip.ID?)] = []
 var deletes: [Clip.ID] = []
 init(clips: [Clip]) { self.clips = clips; state = PickerState(clips: clips, initialSelection: 0) }
 func move(_ id: Clip.ID, before target: Clip.ID?) { moves.append((id,target)) }
 func delete(_ id: Clip.ID) { deletes.append(id) }
}

struct Fixture: View {
 let model: PickerModel
 var body: some View {
  VStack(spacing: 0) {
   Text("Filter").frame(height: 50)
   ScrollView {
    LazyVStack(spacing: 2) {
     ForEach(model.clips) { clip in
      Text("Fixture").frame(maxWidth: .infinity).frame(height: 44)
       .background { GeometryReader { g in
        Color.clear.preference(key: PickerGeometryKey.self, value: PickerGeometry(rows: [clip.id: g.frame(in: .named("picker"))]))
       } }
     }
    }.padding(6)
   }.background { GeometryReader { g in
    Color.clear.preference(key: PickerGeometryKey.self, value: PickerGeometry(viewport: g.frame(in: .named("picker"))))
   } }
   Text("Footer").frame(height: 40)
  }.frame(width: 560, height: 440).coordinateSpace(name: "picker")
   .onPreferenceChange(PickerGeometryKey.self) { model.geometry = $0 }
 }
}

@main struct Checks {
 @MainActor static func main() {
  _ = NSApplication.shared
  let clips = (0..<30).map { i in
   Clip(capturedAt: .now, contentHash: "\(i)", items: [], preview: ClipPreview(text: "\(i)", types: []), searchText: "\(i)", sourceApp: nil)
  }
  let model = PickerModel(clips: clips)
  let panel = PickerPanel(contentRect: NSRect(x: 200, y: 200, width: 560, height: 440), styleMask: [.borderless], backing: .buffered, defer: false)
  let host = NSHostingView(rootView: Fixture(model: model))
  host.safeAreaRegions = []
  panel.contentView = host
  panel.orderFront(nil)
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  var pointer = NSPoint.zero
  let gesture = PickerArrangement(panel: panel, model: model, pointerLocation: { pointer })
  func point(_ index: Int, fraction: CGFloat = 0.5) -> NSPoint {
   let rect = model.geometry.rows[clips[index].id]!
   let local = NSPoint(x: rect.minX + 70, y: rect.minY + rect.height * fraction)
   return panel.convertPoint(toScreen: host.convert(local, to: nil))
  }
  func event(_ type: NSEvent.EventType, at location: NSPoint) {
   pointer = location
   _ = gesture.handle(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: location), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
  }
  // Every visible row must resolve independently, rather than sharing the viewport frame.
  for destination in 0..<6 {
   event(.leftMouseDown, at: point(6))
   event(.leftMouseDragged, at: point(destination, fraction: 0.2))
   precondition(model.draggedID == clips[6].id)
   precondition(model.insertionID == clips[destination].id)
   event(.leftMouseUp, at: point(destination, fraction: 0.2))
   precondition(model.moves.last!.0 == clips[6].id && model.moves.last!.1 == clips[destination].id)
  }
  let outside = NSPoint(x: panel.frame.maxX + 80, y: panel.frame.midY)
  event(.leftMouseDown, at: point(1))
  event(.leftMouseDragged, at: outside)
  precondition(model.insertionID == nil)
  event(.leftMouseDragged, at: point(4, fraction: 0.2))
  precondition(model.insertionID == clips[4].id)
  event(.leftMouseUp, at: point(4, fraction: 0.2))
  precondition(model.deletes.isEmpty)
  // Interior header drops don't delete or move.
  let count = model.moves.count
  event(.leftMouseDown, at: point(1))
  let header = panel.convertPoint(toScreen: host.convert(NSPoint(x: 100, y: 20), to: nil))
  event(.leftMouseDragged, at: header)
  event(.leftMouseUp, at: header)
  precondition(model.moves.count == count && model.deletes.isEmpty)
  event(.leftMouseDown, at: point(2))
  event(.leftMouseDragged, at: outside)
  gesture.cancel()
  event(.leftMouseUp, at: outside)
  precondition(model.deletes.isEmpty)
  event(.leftMouseDown, at: point(3))
  event(.leftMouseDragged, at: outside)
  event(.leftMouseUp, at: outside)
  precondition(model.deletes == [clips[3].id])
  gesture.cancel()
  // Exercise geometry after scrolling, including a window away from its original origin.
  func findScroll(_ view: NSView) -> NSScrollView? {
   if let scroll = view as? NSScrollView { return scroll }
   return view.subviews.lazy.compactMap { findScroll($0) }.first
  }
  let scroll = findScroll(host)!
  scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
  scroll.reflectScrolledClipView(scroll.contentView)
  panel.setFrameOrigin(NSPoint(x: 40, y: 90))
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))
  let visible = model.geometry.rows.filter { model.geometry.viewport.contains($0.value) }.sorted { $0.value.minY < $1.value.minY }
  precondition(visible.count >= 3)
  let source = clips.firstIndex { $0.id == visible.last!.key }!
  let destination = clips.firstIndex { $0.id == visible.first!.key }!
  precondition(destination > 0)
  event(.leftMouseDown, at: point(source))
  event(.leftMouseDragged, at: point(destination, fraction: 0.2))
  precondition(model.insertionID == clips[destination].id)
  event(.leftMouseUp, at: point(destination, fraction: 0.2))
  precondition(model.moves.last!.1 == clips[destination].id)
  model.state.setQuery("1", clips: clips, stickySelection: 0)
  let beforeFilterMoveCount = model.moves.count
  event(.leftMouseDown, at: point(source))
  event(.leftMouseDragged, at: point(destination, fraction: 0.2))
  precondition(model.insertionID == nil)
  event(.leftMouseUp, at: point(destination, fraction: 0.2))
  precondition(model.moves.count == beforeFilterMoveCount)
  gesture.cancel()
  panel.orderOut(nil)
  print("Picker geometry and gesture checks passed")
 }
}
