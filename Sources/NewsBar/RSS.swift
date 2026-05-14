import Foundation

enum RSSError: Error, LocalizedError {
    case http(Int)
    case parse
    case notFound

    var errorDescription: String? {
        switch self {
        case .http(let c): return "HTTP \(c)"
        case .parse: return "フィードを解析できませんでした"
        case .notFound: return "フィードが見つかりません"
        }
    }
}

enum RSS {
    struct Parsed {
        var feedTitle: String?
        var items: [NewsItem]
    }

    static func fetch(url urlString: String) async throws -> Parsed {
        guard let url = URL(string: urlString) else { throw RSSError.notFound }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 NewsBar", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RSSError.http(http.statusCode)
        }
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else { throw RSSError.parse }
        return Parsed(feedTitle: delegate.feedTitle, items: delegate.items)
    }

    /// RSS 2.0 と Atom の両方を雑に拾う SAX デリゲート。
    private final class Delegate: NSObject, XMLParserDelegate {
        var feedTitle: String?
        var items: [NewsItem] = []

        // 状態
        private var current: String = ""
        private var inItem = false
        private var inChannel = false  // RSS の channel/title はフィードタイトル

        private var entryTitle: String = ""
        private var entryLink: String = ""
        private var entryGuid: String = ""
        private var entryPubDate: String = ""
        private var depth: Int = 0
        private var itemDepth: Int = 0
        private var titleAssignedToFeed = false

        func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName q: String?, attributes attrs: [String: String]) {
            depth += 1
            let name = el.lowercased()
            current = ""
            switch name {
            case "item", "entry":
                inItem = true
                itemDepth = depth
                entryTitle = ""; entryLink = ""; entryGuid = ""; entryPubDate = ""
            case "channel", "feed":
                inChannel = true
            case "link":
                if inItem {
                    // Atom: link は属性 href にある
                    if let href = attrs["href"] { entryLink = href }
                }
            default: break
            }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) {
            current += s
        }

        func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName q: String?) {
            let name = el.lowercased()
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if inItem {
                switch name {
                case "title": entryTitle = text
                case "link":
                    if entryLink.isEmpty { entryLink = text }
                case "guid", "id": entryGuid = text
                case "pubdate", "published", "updated": entryPubDate = text
                case "item", "entry":
                    let id = !entryGuid.isEmpty ? entryGuid : entryLink
                    let url = URL(string: entryLink)
                    items.append(NewsItem(
                        id: id.isEmpty ? UUID().uuidString : id,
                        title: entryTitle,
                        link: url,
                        publishedAt: Self.parseDate(entryPubDate)
                    ))
                    inItem = false
                default: break
                }
            } else if inChannel {
                if name == "title", !titleAssignedToFeed, !text.isEmpty {
                    feedTitle = text
                    titleAssignedToFeed = true
                } else if name == "channel" || name == "feed" {
                    inChannel = false
                }
            }
            current = ""
            depth -= 1
        }

        private static let rfc822: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return f
        }()

        private static func parseDate(_ s: String) -> Date? {
            if s.isEmpty { return nil }
            if let d = rfc822.date(from: s) { return d }
            return ISO8601DateFormatter().date(from: s)
        }
    }
}
