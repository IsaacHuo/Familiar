import ImageIO
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Immutable managed URLs/version IDs make memory-only thumbnails safe to reuse.
actor FamiliarThumbnailLoader {
    static let shared = FamiliarThumbnailLoader()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 120 }

    private struct Flight {
        let id: UUID
        let cacheGeneration: UUID
        let task: Task<UIImage?, Never>
        var waiters: Set<UUID>
    }
    private var flights: [String: Flight] = [:]
    private var tail: Task<UIImage?, Never>?
    private var tailID: UUID?
    private var cacheGeneration = UUID()

    func purge() { cacheGeneration = UUID(); cache.removeAllObjects() }

    func image(url: URL, pixels: Int, identity: String = "") async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let pixels = min(max(pixels, 32), 3072)
        let key = "\(url.absoluteString):\(identity):\(pixels)"
        if let image = cache.object(forKey: key as NSString) { return image }
        let waiter = UUID()
        let flight: Flight
        if var existing = flights[key] {
            existing.waiters.insert(waiter); flights[key] = existing; flight = existing
        } else {
            let predecessor = tail, id = UUID()
            // One asset preparation at a time; cancellation skips queued work.
            let job = Task.detached(priority: .utility) { () -> UIImage? in
                _ = await predecessor?.value
                guard !Task.isCancelled else { return nil }
                if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                    return Self.downsample(url: url, pixels: pixels)
                }
                guard !["html", "htm"].contains(url.pathExtension.lowercased()) else { return nil }
                let request = QLThumbnailGenerator.Request(fileAt: url, size: .init(width: pixels, height: pixels), scale: 1, representationTypes: .thumbnail)
                // Queued jobs cancel before preparation. A system Quick Look
                // request already in progress may finish; nobody retains its image
                // once the last waiter leaves.
                return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
            }
            flight = Flight(id: id, cacheGeneration: cacheGeneration, task: job, waiters: [waiter])
            flights[key] = flight; tail = job; tailID = id
        }
        let image = await withTaskCancellationHandler { await flight.task.value } onCancel: {
            Task { await self.cancel(waiter: waiter, key: key, flightID: flight.id) }
        }
        if flights[key]?.id == flight.id {
            flights.removeValue(forKey: key)
            if let image, cacheGeneration == flight.cacheGeneration {
                cache.setObject(image, forKey: key as NSString,
                    cost: (image.cgImage?.bytesPerRow ?? pixels * 4) * (image.cgImage?.height ?? pixels))
            }
        }
        if tailID == flight.id { tail = nil; tailID = nil }
        return Task.isCancelled ? nil : image
    }

    private func cancel(waiter: UUID, key: String, flightID: UUID) {
        guard var flight = flights[key], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key); flight.task.cancel()
        } else { flights[key] = flight }
    }

    nonisolated static func downsample(url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct FamiliarFileThumbnail: View {
    @Environment(\.displayScale) private var scale
    let url: URL?
    let identity: String
    let symbol: String
    var side: CGFloat = 44
    @State private var image: UIImage?
    private var key: String { "\(url?.absoluteString ?? ""):\(identity):\(Int(side * scale))" }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: symbol).font(.system(size: side * 0.5)).foregroundStyle(.secondary) }
        }
        .frame(width: side, height: side).background(FamiliarTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
        .task(id: key) {
            image = nil
            guard let url else { return }
            let result = await FamiliarThumbnailLoader.shared.image(url: url, pixels: Int(side * scale), identity: identity)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}
