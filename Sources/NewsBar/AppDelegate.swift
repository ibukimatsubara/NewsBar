import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = NewsStore()
    private let tickerView = TickerView()
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
        if store.visibleFeeds.isEmpty {
            tickerView.stopAnimation()
            tickerView.removeFromSuperview()
            statusItem.length = NSStatusItem.variableLength
            button.title = "NewsBar"
            button.target = self
            button.action = #selector(togglePopover)
            return
        }
        // ticker
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = nil
        // ボタン自身のクリックは無効化（クリックは TickerView 側で受ける）
        button.target = nil
        button.action = nil

        let chW = Self.monoCellWidth
        let width = CGFloat(store.tickerWidth) * chW + 8
        statusItem.length = width
        let frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
        tickerView.frame = frame
        if tickerView.superview !== button {
            button.addSubview(tickerView)
        }
        let (strip, ranges) = store.tickerStripWithRanges(font: Self.monoFont)
        tickerView.setAttributedString(strip)
        tickerView.clickableRanges = ranges
        tickerView.pixelsPerSecond = chW / max(store.tickerStepInterval, 0.001)
        tickerView.gapPixels = max(CGFloat(store.tickerWidth) * chW / 2, 60)
        tickerView.startAnimation()
    }
}
