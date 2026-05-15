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
    /// 文字列を一度だけラスタライズしたビットマップ。アニメ中は draw(at:) せず、これを使い回す。
    private var cachedImage: NSImage?
    private var pixelOffset: CGFloat = 0
    private var animTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var isPausedForSleep = false

    deinit {
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver  { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    func setAttributedString(_ s: NSAttributedString) {
        attributedString = s
        stringSize = s.size()
        cachedImage = renderToImage(s, size: stringSize)
        needsDisplay = true
    }

    private func renderToImage(_ s: NSAttributedString, size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let img = NSImage(size: size)
        img.lockFocus()
        s.draw(at: .zero)
        img.unlockFocus()
        return img
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard stringSize.width > 0, let img = cachedImage else { return }
        let trackWidth = stringSize.width + gapPixels
        let offset = pixelOffset.truncatingRemainder(dividingBy: trackWidth)
        let y = (bounds.height - stringSize.height) / 2
        // デバイスピクセルにスナップしないとプリレンダ画像が補間されてボヤける。
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let snap: (CGFloat) -> CGFloat = { (round($0 * scale) / scale) }
        let ctx = NSGraphicsContext.current
        let prevInterp = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        img.draw(at: NSPoint(x: snap(-offset), y: snap(y)),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        img.draw(at: NSPoint(x: snap(-offset + trackWidth), y: snap(y)),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        if let p = prevInterp { ctx?.imageInterpolation = p }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onLeftClick?()
            return
        }
        openURLAt(event: event)
    }

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
        installSleepObserversIfNeeded()
        // 60FPS → 30FPS。menu bar の流し見では体感差はほぼなく CPU は半減。
        let interval: TimeInterval = 1.0 / 30.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPausedForSleep else { return }
                self.pixelOffset += self.pixelsPerSecond * CGFloat(interval)
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }

    private func installSleepObserversIfNeeded() {
        let nc = NSWorkspace.shared.notificationCenter
        if sleepObserver == nil {
            sleepObserver = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isPausedForSleep = true }
            }
        }
        if wakeObserver == nil {
            wakeObserver = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                          object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isPausedForSleep = false }
            }
        }
    }
}
