import Foundation

/// Reads the feeds of an OPML file, such as the subscriptions of NetNewsWire.
public enum OPMLImport {

    /// The OPML file of the On My Mac account of NetNewsWire.
    public static var netNewsWireFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.ranchero.NetNewsWire-Evergreen/Data/Library/Application Support/NetNewsWire/Accounts/OnMyMac/Subscriptions.opml")
    }

    /// Each feed in the file, in folders too.
    public static func feeds(in file: URL) throws -> [OPMLFeedSpecifier] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw FeedError("Piper cannot read \(file.lastPathComponent). If it is the NetNewsWire file, give Piper Full Disk Access, or export the subscriptions from NetNewsWire and import that file.")
        }
        let document = try OPMLParser.parseOPML(with: ParserData(url: file.absoluteString, data: data))
        return feeds(of: document)
    }

    private static func feeds(of item: OPMLItem) -> [OPMLFeedSpecifier] {
        (item.feedSpecifier.map { [$0] } ?? []) + (item.children ?? []).flatMap(feeds(of:))
    }
}
