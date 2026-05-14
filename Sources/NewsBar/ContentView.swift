import SwiftUI
import AppKit
import ServiceManagement

struct ContentView: View {
    @EnvironmentObject var store: NewsStore
    @State private var newURL: String = ""
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            feedList
            Divider()
            addBar
            Divider()
            footer
            if showSettings {
                Divider()
                SettingsView().padding(12)
            }
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack {
            Text("NewsBar").font(.headline)
            Spacer()
            Button(action: { store.toggleFocus() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.focusMode ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(store.focusMode ? "集中モード ON" : "集中モード OFF")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.secondary.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            Button("更新") {
                Task { await store.refreshAll() }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var feedList: some View {
        List {
            ForEach(store.feeds) { feed in
                FeedRow(feed: feed)
            }
            .onMove(perform: store.move)
        }
        .listStyle(.plain)
        .frame(minHeight: 240, idealHeight: CGFloat(min(max(store.feeds.count, 3) * 56, 480)), maxHeight: 480)
    }

    private var addBar: some View {
        HStack {
            TextField("RSS / Atom の URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addFeed() }
            Button("追加") { addFeed() }
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button(action: { showSettings.toggle() }) {
                Label("設定", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button("終了") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func addFeed() {
        let s = newURL
        newURL = ""
        store.add(url: s)
    }
}

struct FeedRow: View {
    @EnvironmentObject var store: NewsStore
    let feed: Feed
    @State private var draftNickname: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundColor(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                TextField(feed.feedTitle ?? feed.url, text: $draftNickname)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused($nameFocused)
                    .onAppear { draftNickname = feed.nickname ?? "" }
                    .onChange(of: nameFocused) { focused in
                        if !focused { store.setNickname(feed, to: draftNickname) }
                    }
                    .onSubmit {
                        store.setNickname(feed, to: draftNickname)
                        nameFocused = false
                    }
                Text(feed.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { feed.visible },
                set: { _ in store.toggleVisible(feed) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button(action: { store.remove(feed) }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .opacity(feed.visible ? 1.0 : 0.5)
    }

    @ViewBuilder private var statusLine: some View {
        if let err = feed.lastError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow).font(.caption2)
                Text("取得失敗: \(err)").font(.caption2).foregroundColor(.yellow).lineLimit(1)
            }
        } else {
            let latest = feed.items.compactMap { $0.publishedAt }.max()
            let latestStr = latest.map { " · 最新 " + Self.latestFmt.string(from: $0) } ?? ""
            Text("\(feed.items.count) 件" + (feed.lastFetched.map { " · " + Self.timeFmt.string(from: $0) } ?? "") + latestStr)
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    private static let latestFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"; return f
    }()
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: NewsStore
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("ログイン時に自動起動", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.set(enabled: newValue)
                    launchAtLogin = LoginItem.isEnabled
                }
            sliderRow(label: "バー幅",
                      value: Binding(get: { Double(store.tickerWidth) },
                                     set: { store.tickerWidth = Int($0) }),
                      range: 20...600, step: 10,
                      format: { "\(Int($0))桁" })
            sliderRow(label: "速度",
                      value: Binding(get: { store.tickerStepInterval * 1000 },
                                     set: { store.tickerStepInterval = $0 / 1000 }),
                      range: 20...300, step: 10,
                      format: { "\(Int($0))ms" })
            sliderRow(label: "更新間隔",
                      value: Binding(get: { Double(store.refreshIntervalMinutes) },
                                     set: { store.refreshIntervalMinutes = Int($0) }),
                      range: 1...60, step: 1,
                      format: { "\(Int($0))分" })
            sliderRow(label: "表示期間",
                      value: Binding(get: { Double(store.maxAgeHours) },
                                     set: { store.maxAgeHours = Int($0) }),
                      range: 1...240, step: 1,
                      format: { h in
                          let i = Int(h)
                          return i < 48 ? "\(i)時間以内" : "\(i)時間 (\(i/24)日)"
                      })
            Text("左クリック: 見出しをブラウザで開く  ／  右クリック（または Ctrl+クリック）: この設定を開閉")
                .font(.caption2).foregroundColor(.secondary)
        }
        .font(.caption)
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 56, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(format(value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 56, alignment: .trailing)
                .foregroundColor(.secondary)
        }
    }
}
