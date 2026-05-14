import AppKit

@MainActor
final class TickerView: NSView {
    var pixelsPerSecond: CGFloat = 90
    var gapPixels: CGFloat = 60
    /// クリックで開く URL の x 座標範囲（帯の中での絶対位置）
    var clickableRanges: [(range: ClosedRange<CGFloat>, url: URL)] = []
    /// 左クリック時に呼ばれる（ポップオーバー開閉用）
    var onLeftClick: (() -> Void)?

    private(set) var attributedString: NSAttributedString = NSAttributedString()
    private var stringSize: NSSize = .zero
    private var pixelOffset: CGFloat = 0
    private var animTimer: Timer?

    func setAttributedString(_ s: NSAttributedString) {
        attributedString = s
        stringSize = s.size()
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard stringSize.width > 0 else { return }
        let trackWidth = stringSize.width + gapPixels
        let offset = pixelOffset.truncatingRemainder(dividingBy: trackWidth)
        let y = (bounds.height - stringSize.height) / 2
        attributedString.draw(at: NSPoint(x: -offset, y: y))
        attributedString.draw(at: NSPoint(x: -offset + trackWidth, y: y))
    }

    /// 左クリックでカーソル位置の見出しをブラウザで開く。
    override func mouseDown(with event: NSEvent) {
        // Ctrl+クリックは macOS の慣習で右クリック扱い → 設定
        if event.modifierFlags.contains(.control) {
            onLeftClick?()
            return
        }
        openURLAt(event: event)
    }

    /// 右クリックで設定ダイアログを開く。
    override func rightMouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    private func openURLAt(event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let trackWidth = stringSize.width + gapPixels
        guard trackWidth > 0 else { return }
        let offset = pixelOffset.truncatingRemainder(dividingBy: trackWidth)
        var trackX = local.x + offset
        trackX = trackX.truncatingRemainder(dividingBy: trackWidth)
        if trackX < 0 { trackX += trackWidth }
        for (range, url) in clickableRanges where range.contains(trackX) {
            NSWorkspace.shared.open(url)
            return
        }
    }

    func startAnimation() {
        if animTimer != nil { return }
        let interval: TimeInterval = 1.0 / 60.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pixelOffset += self.pixelsPerSecond * CGFloat(interval)
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
