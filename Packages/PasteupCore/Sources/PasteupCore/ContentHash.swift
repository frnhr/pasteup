import CryptoKit
import Foundation

public enum ContentHash {
	/// SHA-256 over every item's types and data. Item and representation boundaries are part of the hash,
	/// so `[[a, b]]` and `[[a], [b]]` hash differently.
	public static func of(_ items: [RawItem]) -> String {
		var hasher = SHA256()
		for item in items {
			hasher.update(data: Data("item:\(item.count)\n".utf8))
			for representation in item {
				hasher.update(data: Data("\(representation.type)\n\(representation.data.count)\n".utf8))
				hasher.update(data: representation.data)
			}
		}
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}
}
