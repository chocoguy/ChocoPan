import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers


nonisolated enum ImageTier: String, Sendable {
    case grid
    case showCase

    var maxPixelSize: Int {
        switch self {
        case .grid: 640
        case .showCase: 1920
        }
    }
}

//Some sort of a unique key, prevents duplicate conflicts
nonisolated struct ImageKey: Hashable, Sendable {
    let basename: String

    static func thumbnail(episodeId: UUID, fileModified: Date, tier: ImageTier) -> ImageKey {
        ImageKey(basename: "ep-\(episodeId.uuidString)-\(Int(fileModified.timeIntervalSince1970))-\(tier.rawValue)")
    }

    static func poster(urlString: String) -> ImageKey {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return ImageKey(basename: "poster-\(hex)")
    }

    var cacheKey: NSString { basename as NSString }
}

nonisolated struct CacheStatistics: Sendable {
    let fileCount: Int
    let byteCount: Int

    var description: String {
        guard fileCount > 0 else { return "empty" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "\(fileCount) image\(fileCount == 1 ? "" : "s") · \(size)"
    }
}

nonisolated enum ImageCacheError: Error, CustomStringConvertible {
    case encoderUnavailable
    case encodeFailed
    case decodeFailed
    case badResponse(Int)

    var description: String {
        switch self {
        case .encoderUnavailable: "no image encoder available"
        case .encodeFailed: "could not write image"
        case .decodeFailed: "could not decode image data"
        case .badResponse(let code): "server returned \(code)"
        }
    }
}


actor ImageCacher {
    static let shared = ImageCacher()
    static let posterMaxPixelSize = 720
    private static let compressionQuality = 0.99
    private static let evictionTargetFraction = 0.8

    private let directory: URL
    private let format: StorageFormat
    private let memory = NSCache<NSString, CGImage>()
    private var inFlight: [ImageKey: Task<CGImage, Error>] = [:]

    init(memoryLimitBytes: Int = 64 * 1024 * 1024) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        format = StorageFormat.supported
        memory.totalCostLimit = memoryLimitBytes
        Self.sweepTemporaries(in: directory)
    }

    func image(
        for key: ImageKey,
        produce: @escaping @Sendable () async throws -> CGImage
    ) async throws -> CGImage {
        if let cached = memory.object(forKey: key.cacheKey) {
            return cached
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let url = fileURL(for: key)
        let format = self.format

        let task = Task<CGImage, Error> {
            if let onDisk = Self.read(from: url) {
                Self.touch(url)
                return onDisk
            }
            let produced = try await produce()
            do {
                try Self.write(produced, to: url, format: format)
            } catch {
                // Non-fatal: the caller still gets its image, but the disk cache is not doing its
                // job, so say so rather than silently refetching on every launch forever.
                print("ImageCacher: could not cache \(url.lastPathComponent): \(error)")
                Self.sweepTemporaries(in: url.deletingLastPathComponent())
            }
            return produced
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let image = try await task.value
        memory.setObject(image, forKey: key.cacheKey, cost: Self.cost(of: image))
        return image
    }

  
    
    
    
    
    func thumbnail(
        episodeId: UUID,
        fileModified: Date,
        videoURL: URL,
        tier: ImageTier
    ) async throws -> CGImage {
        let key = ImageKey.thumbnail(episodeId: episodeId, fileModified: fileModified, tier: tier)
        return try await image(for: key) {
            try await VideoThumbnailer.thumbnail(for: videoURL, maxWidth: tier.maxPixelSize).image
        }
    }


    func poster(at remoteURL: URL) async throws -> CGImage {
        try await image(for: .poster(urlString: remoteURL.absoluteString)) {
            try await Self.fetchPoster(at: remoteURL)
        }
    }

    
    
    nonisolated static func fetchPoster(at remoteURL: URL) async throws -> CGImage {
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImageCacheError.badResponse(http.statusCode)
        }
        return try decode(data, maxPixelSize: posterMaxPixelSize)
    }


    
    func evictIfNeeded(limitMB: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return }

        var entries: [(url: URL, size: Int, modified: Date)] = []
        var total = 0
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { continue }
            entries.append((url, size, values.contentModificationDate ?? .distantPast))
            total += size
        }

        let limit = limitMB * 1024 * 1024
        guard total > limit else { return }

        let target = Int(Double(limit) * Self.evictionTargetFraction)
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard total > target else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// What is actually on disk right now, for the cache section in Settings.
    func statistics() -> CacheStatistics {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return CacheStatistics(fileCount: 0, byteCount: 0) }

        let sizes = contents.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        return CacheStatistics(fileCount: sizes.count, byteCount: sizes.reduce(0, +))
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

 

    private func fileURL(for key: ImageKey) -> URL {
        directory
            .appendingPathComponent(key.basename, isDirectory: false)
            .appendingPathExtension(format.pathExtension)
    }

    private nonisolated static func read(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private nonisolated static func write(_ image: CGImage, to url: URL, format: StorageFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageCacheError.encoderUnavailable
        }

        let options = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCacheError.encodeFailed
        }
    }


    
    private nonisolated static func decode(_ data: Data, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageCacheError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageCacheError.decodeFailed
        }
        return image
    }

 
    
    /// `CGImageDestination` writes through a dot-prefixed scratch file and only cleans it up on a
    /// successful finalize. A failed encoder leaves one behind per write, and they are invisible to
    /// `evictIfNeeded`, which skips hidden files.
    private nonisolated static func sweepTemporaries(in directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where url.lastPathComponent.hasPrefix(".") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private nonisolated static func touch(_ url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) > 86_400 else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private nonisolated static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}



nonisolated enum StorageFormat: Sendable {
    case heic
    case jpeg

    /// Advertised support is not the same as working support: the tvOS simulator lists `public.heic`
    /// among its destination types but fails at finalize, so every write used to die and leave a
    /// zero-byte scratch file behind. Encode a pixel and see what actually comes out.
    static let supported: StorageFormat = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        if identifiers.contains(UTType.heic.identifier), canEncode(.heic) {
            return .heic
        }
        return .jpeg
    }()

    private static func canEncode(_ format: StorageFormat) -> Bool {
        guard let image = onePixel else { return false }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.identifier as CFString,
            1,
            nil
        ) else { return false }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) && data.length > 0
    }

    private static var onePixel: CGImage? {
        var pixel: [UInt8] = [0, 0, 0, 255]
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return pixel.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )?.makeImage()
        }
    }

    var identifier: String {
        switch self {
        case .heic: UTType.heic.identifier
        case .jpeg: UTType.jpeg.identifier
        }
    }

    var pathExtension: String {
        switch self {
        case .heic: "heic"
        case .jpeg: "jpg"
        }
    }
}
