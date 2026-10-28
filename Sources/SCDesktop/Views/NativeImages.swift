import AppKit
import ImageIO
import SwiftUI

/// Network artwork drawn straight into a CALayer, decoded off the main
/// thread and downscaled once (see ArtworkCache).
struct RemoteImage: NSViewRepresentable {
    var url: String?
    var size: Int
    var radius: Int = 4

    func makeNSView(context: Context) -> ArtworkView { ArtworkView() }

    func updateNSView(_ view: ArtworkView, context: Context) {
        view.radius = CGFloat(radius)
        view.placeholder = Theme.current.surface.ns
        // Small thumbs don't need the 300px artwork.
        view.load(Format.artwork(url, size: size > 60 ? "t300x300" : "t120x120"), pixels: size * 2)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArtworkView, context: Context) -> CGSize? {
        CGSize(width: Double(size), height: Double(size))
    }

    static func dismantleNSView(_ view: ArtworkView, coordinator: ()) {
        view.cancelLoad()
    }
}

final class ArtworkView: NSView {
    override var wantsUpdateLayer: Bool { true }

    var radius: CGFloat = 4 {
        didSet { if radius != oldValue { layer?.cornerRadius = radius } }
    }
    var placeholder = NSColor.gray {
        didSet { if placeholder != oldValue, layer?.contents == nil { layer?.backgroundColor = placeholder.cgColor } }
    }
    private var url: String?
    private var pixels = 0
    private var loadTask: Task<Void, Never>?
    private var image: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // AppKit must not allocate a drawing surface on every resize/scroll redraw.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(_ url: String?, pixels: Int) {
        guard url != self.url || pixels != self.pixels else { return }
        cancelLoad()
        self.url = url
        self.pixels = pixels
        guard let url else {
            show(nil)
            return
        }
        if let hit = ArtworkCache.shared.cached(url, pixels: pixels) {
            show(hit)
            return
        }
        show(nil)
        loadTask = Task { [weak self] in
            let image = await ArtworkCache.shared.image(url, pixels: pixels)
            guard !Task.isCancelled, let self, self.url == url, self.pixels == pixels else { return }
            self.show(image)
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func show(_ image: CGImage?) {
        self.image = image
        updateLayer()
    }

    override func updateLayer() {
        // Artwork arriving during a scroll should not start another compositing animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        layer?.backgroundColor = image == nil ? placeholder.cgColor : nil
        CATransaction.commit()
    }
}

/// Decoded, downscaled artwork in memory (NSCache evicts under pressure)
/// on top of the on-disk ImageCache.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    // Serial decoding keeps a newly opened page from flooding the CPU with thumbnails.
    private let decodeQueue = DispatchQueue(label: "SCDesktop.artwork", qos: .userInitiated)

    private let memory: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func cached(_ url: String, pixels: Int) -> CGImage? {
        memory.object(forKey: "\(pixels)|\(url)" as NSString)
    }

    func image(_ url: String, pixels: Int) async -> CGImage? {
        if let hit = cached(url, pixels: pixels) { return hit }
        let key = "\(pixels)|\(url)"
        if let task = inflight[key] { return await task.value }
        let task = Task<CGImage?, Never> {
            guard let file = await ImageCache.shared.file(for: url), !Task.isCancelled else { return nil }
            let image: CGImage? = await withCheckedContinuation { continuation in
                decodeQueue.async {
                    let image: CGImage? = autoreleasepool {
                        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: pixels,
                        ]
                        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                    }
                    continuation.resume(returning: image)
                }
            }
            return Task.isCancelled ? nil : image
        }
        inflight[key] = task
        let image = await task.value
        // A cache clear can replace this request while its decode is finishing.
        guard !task.isCancelled else { return nil }
        inflight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    func clear() {
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        memory.removeAllObjects()
    }
}

/// SF Symbol tinted with the theme.
struct Icon: View {
    var name: String
    var size: Int = 18
    var color: NSColor? = nil

    var body: some View {
        Image(systemName: name)
            .font(.system(size: CGFloat(size), weight: .semibold))
            .foregroundStyle(Color(nsColor: color ?? Theme.current.text.ns))
            // Play ↔ pause, heart on/off: swap symbols smoothly.
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeOut(duration: 0.15), value: name)
            .animation(.easeOut(duration: 0.15), value: color)
            .frame(width: CGFloat(size), height: CGFloat(size))
    }
}

/// Clickable icon without a button bezel.
struct IconButton: View {
    var name: String
    var size: Int = 18
    var color: NSColor? = nil
    var help: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(name: name, size: size, color: color)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

extension NSColor {
    static let soundcloud = NSColor(red: 1, green: 0.333, blue: 0, alpha: 1)
}
