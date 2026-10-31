// Saves and restores the general pasteboard with all its items and types, so a promo take can put
// your clipboard back afterwards. Pasteup then sees the same content as its newest clip and records nothing.
//
//   clipboard save <file.plist>       Writes every item's types and data to a property list.
//   clipboard restore <file.plist>    Puts them back on the pasteboard.
//   clipboard clip <history folder>   Puts Pasteup's newest clip back on the pasteboard, from its stored blobs.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
	FileHandle.standardError.write(Data("usage: clipboard save|restore <file.plist> | clipboard clip <history folder>\n".utf8))
	exit(2)
}
let pasteboard = NSPasteboard.general

func write(_ items: [[String: Data]]) {
	let pasteboardItems = items.map { types in
		let item = NSPasteboardItem()
		for (type, data) in types {
			item.setData(data, forType: NSPasteboard.PasteboardType(type))
		}
		return item
	}
	pasteboard.clearContents()
	pasteboard.writeObjects(pasteboardItems)
}

switch arguments[1] {
case "save":
	let items: [[String: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
		Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type.rawValue, $0) } })
	}
	let data = try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
	try data.write(to: URL(filePath: arguments[2]))
case "restore":
	let data = try Data(contentsOf: URL(filePath: arguments[2]))
	guard let items = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Data]] else {
		FileHandle.standardError.write(Data("clipboard: \(arguments[2]) isn't a saved clipboard\n".utf8))
		exit(1)
	}
	write(items)
case "clip":
	struct Representation: Decodable {
		let type: String
		let blobName: String
	}
	struct Item: Decodable {
		let representations: [Representation]
	}
	struct Clip: Decodable {
		let id: UUID
		let items: [Item]
	}
	struct History: Decodable {
		let clips: [Clip]
	}
	let folder = URL(filePath: arguments[2], directoryHint: .isDirectory)
	let history = try JSONDecoder().decode(History.self, from: Data(contentsOf: folder.appending(path: "history.json")))
	guard let clip = history.clips.first else {
		FileHandle.standardError.write(Data("clipboard: the history is empty\n".utf8))
		exit(1)
	}
	let blobs = folder.appending(path: "blobs/\(clip.id.uuidString)", directoryHint: .isDirectory)
	write(try clip.items.map { item in
		Dictionary(uniqueKeysWithValues: try item.representations.map { ($0.type, try Data(contentsOf: blobs.appending(path: $0.blobName))) })
	})
default:
	FileHandle.standardError.write(Data("clipboard: unknown command \(arguments[1])\n".utf8))
	exit(2)
}
// Some apps read pasteboard data lazily; give them a moment before the process exits.
Thread.sleep(forTimeInterval: 0.5)
