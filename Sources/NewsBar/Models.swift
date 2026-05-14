import Foundation

struct Feed: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// RSS / Atom の URL
    var url: String
    /// ユーザー指定のニックネーム。空ならフィード自身の title を使う。
    var nickname: String?
    var visible: Bool = true

    // 取得後にランタイムで埋める
    var feedTitle: String?
    var items: [NewsItem] = []
    var lastError: String?
    var lastFetched: Date?

    enum CodingKeys: String, CodingKey {
        case id, url, nickname, visible
    }

    var displayName: String {
        if let n = nickname, !n.isEmpty { return n }
        if let t = feedTitle, !t.isEmpty { return t }
        return URL(string: url)?.host ?? url
    }
}

struct NewsItem: Identifiable, Equatable {
    let id: String  // guid or link
    let title: String
    let link: URL?
    let publishedAt: Date?
}
