import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = NewsStore()
    private let tickerView = TickerView()
    private enum BarMode { case ticker, idle }
    private var currentMode: BarMode?
    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static var monoCellWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: monoFont]).width
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "NewsBar"

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 560, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store)
        )

        tickerView.onLeftClick = { [weak self] in self?.togglePopover() }

        store.onUpdate = { [weak self] in self?.refreshTitle() }
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.synchronize()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let anchor = NSRect(x: button.bounds.maxX - 1, y: 0, width: 1, height: button.bounds.height)
            popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        let nextMode: BarMode = (store.focusMode || store.visibleFeeds.isEmpty) ? .idle : .ticker
        let from = currentMode
        switch nextMode {
        case .idle:   applyIdle(button: button, from: from)
        case .ticker: applyTicker(button: button, from: from)
        }
        currentMode = nextMode
    }

    /// アイコンだけ表示し、クリックでポップオーバーを開くモード。
    private func applyIdle(button: NSStatusBarButton, from: BarMode?) {
        if from == .ticker {
            tickerView.stopAnimation()
            tickerView.removeFromSuperview()
            tickerView.clickableRanges = []
        }
        statusItem.length = NSStatusItem.variableLength
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = NewsStore.newspaperIcon()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
    }

    /// ティッカーをメニューバーに乗せるモード。クリックは TickerView 側で受ける。
    /// 毎回フル再適用する：target/action のリセット、strip/ranges の置換、寸法調整。
    private func applyTicker(button: NSStatusBarButton, from: BarMode?) {
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = nil
        button.target = nil
        button.action = nil

        let chW = Self.monoCellWidth
        let width = CGFloat(store.tickerWidth) * chW + 8
        statusItem.length = width
        tickerView.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
        if tickerView.superview !== button {
            button.addSubview(tickerView)
        }
        let (strip, ranges) = store.tickerStripWithRanges(font: Self.monoFont)
        tickerView.setAttributedString(strip)
        tickerView.clickableRanges = ranges
        tickerView.pixelsPerSecond = chW / max(store.tickerStepInterval, 0.001)
        tickerView.gapPixels = max(CGFloat(store.tickerWidth) * chW / 2, 60)
        if from != .ticker {
            tickerView.startAnimation()
        }
    }
}
