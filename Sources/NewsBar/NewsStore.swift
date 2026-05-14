import Foundation
import AppKit
import Combine

@MainActor
final class NewsStore: ObservableObject {
    @Published var feeds: [Feed] = []
    /// 1セルあたりの秒数 ≒ 速度。
    @Published var tickerStepInterval: TimeInterval = 0.06
    @Published var tickerWidth: Int = 80
    /// 取得間隔（分）
    @Published var refreshIntervalMinutes: Int = 10

    var onUpdate: (() -> Void)?

    private let feedsKey = "NewsBar.feeds.v1"
    private let prefsKey = "NewsBar.prefs.v1"
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init() {
        load()
        $tickerStepInterval.dropFirst().sink { [weak self] _ in self?.savePrefs(); self?.onUpdate?() }.store(in: &cancellables)
        $tickerWidth.dropFirst().sink { [weak self] _ in self?.savePrefs(); self?.onUpdate?() }.store(in: &cancellables)
        $refreshIntervalMinutes.dropFirst().sink { [weak self] _ in self?.savePrefs(); self?.restartRefreshTimer() }.store(in: &cancellables)
    }

    func start() {
        Task { await refreshAll() }
        restartRefreshTimer()
    }

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(refreshIntervalMinutes, 1) * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    // MARK: - CRUD

    func add(url raw: String) {
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !feeds.contains(where: { $0.url == u }) else { return }
        feeds.append(Feed(url: u))
        save()
        onUpdate?()
        Task { await refreshOne(url: u) }
    }

    func remove(_ feed: Feed) {
        feeds.removeAll { $0.id == feed.id }
        save()
        onUpdate?()
    }

    func setNickname(_ feed: Feed, to raw: String) {
        guard let i = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        feeds[i].nickname = trimmed.isEmpty ? nil : trimmed
        save()
        onUpdate?()
    }

    func toggleVisible(_ feed: Feed) {
        guard let i = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[i].visible.toggle()
        save()
        onUpdate?()
    }

    func move(from: IndexSet, to: Int) {
        feeds.move(fromOffsets: from, toOffset: to)
        save()
        onUpdate?()
    }

    // MARK: - Fetch

    func refreshAll() async {
        for feed in feeds where feed.visible {
            await refreshOne(url: feed.url)
        }
        onUpdate?()
    }

    func refreshOne(url: String) async {
        do {
            let parsed = try await RSS.fetch(url: url)
            if let idx = feeds.firstIndex(where: { $0.url == url }) {
                feeds[idx].feedTitle = parsed.feedTitle
                feeds[idx].items = parsed.items
                feeds[idx].lastError = nil
                feeds[idx].lastFetched = Date()
            }
            onUpdate?()
        } catch {
            if let idx = feeds.firstIndex(where: { $0.url == url }) {
                feeds[idx].lastError = error.localizedDescription
                feeds[idx].lastFetched = Date()
            }
            onUpdate?()
        }
    }

    // MARK: - Derived

    var visibleFeeds: [Feed] { feeds.filter { $0.visible } }

    /// ティッカー帯を組み立てる。各記事の x 座標範囲とリンクを併せて返す。
    func tickerStripWithRanges(font mono: NSFont) -> (NSAttributedString, [(range: ClosedRange<CGFloat>, url: URL)]) {
        let track = NSMutableAttributedString()
        var ranges: [(ClosedRange<CGFloat>, URL)] = []
        let sep = "   ●   "
        var cursor: CGFloat = 0
        for (i, feed) in visibleFeeds.enumerated() {
            if i > 0 {
                let s = NSAttributedString(string: sep, attributes: [.font: mono, .foregroundColor: NSColor.tertiaryLabelColor])
                track.append(s)
                cursor += s.size().width
            }
            // 出展タグ
            let tag = NSAttributedString(
                string: "[\(feed.displayName)] ",
                attributes: [.font: mono, .foregroundColor: NSColor.secondaryLabelColor]
            )
            track.append(tag)
            cursor += tag.size().width

            if feed.lastError != nil || feed.items.isEmpty {
                let s = NSAttributedString(
                    string: feed.lastError ?? "（記事なし）",
                    attributes: [.font: mono, .foregroundColor: NSColor.systemYellow]
                )
                track.append(s)
                cursor += s.size().width
                continue
            }
            for (j, item) in feed.items.enumerated() {
                if j > 0 {
                    let s = NSAttributedString(
                        string: "   ／   ",
                        attributes: [.font: mono, .foregroundColor: NSColor.tertiaryLabelColor]
                    )
                    track.append(s); cursor += s.size().width
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: mono,
                    .foregroundColor: NSColor.labelColor
                ]
                let s = NSAttributedString(string: item.title, attributes: attrs)
                let w = s.size().width
                let startX = cursor
                track.append(s)
                cursor += w
                if let link = item.link {
                    ranges.append((startX...(startX + w), link))
                }
            }
        }
        return (track, ranges)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: feedsKey)
        }
        savePrefs()
    }

    private func savePrefs() {
        let prefs: [String: Any] = [
            "tickerStepInterval": tickerStepInterval,
            "tickerWidth": tickerWidth,
            "refreshIntervalMinutes": refreshIntervalMinutes
        ]
        UserDefaults.standard.set(prefs, forKey: prefsKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: feedsKey),
           let arr = try? JSONDecoder().decode([Feed].self, from: data) {
            feeds = arr
        } else {
            feeds = [
                Feed(url: "https://www3.nhk.or.jp/rss/news/cat0.xml", nickname: "NHK"),
                Feed(url: "https://feeds.bbci.co.uk/news/world/rss.xml", nickname: "BBC"),
                Feed(url: "https://hnrss.org/frontpage", nickname: "HN")
            ]
        }
        if let prefs = UserDefaults.standard.dictionary(forKey: prefsKey) {
            if let s = prefs["tickerStepInterval"] as? TimeInterval { tickerStepInterval = min(max(s, 0.02), 0.30) }
            if let w = prefs["tickerWidth"] as? Int { tickerWidth = min(max(w, 20), 600) }
            if let r = prefs["refreshIntervalMinutes"] as? Int { refreshIntervalMinutes = min(max(r, 1), 120) }
        }
    }
}
