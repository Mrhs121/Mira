import Foundation
import ImageIO
import CoreGraphics

private final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class MetadataBox {
    let metadata: ImageMetadata
    init(_ metadata: ImageMetadata) { self.metadata = metadata }
}

/// Synchronous, thread-safe image loading with an in-memory cache.
/// The UI calls this from background queues and only touches AppKit on the main thread.
public final class ImagePipeline: @unchecked Sendable {
    public static let shared = ImagePipeline()

    private let cache = NSCache<NSString, CGImageBox>()
    private let metadataCache = NSCache<NSString, MetadataBox>()

    public init(memoryLimit: Int = 256 * 1024 * 1024) {
        cache.totalCostLimit = memoryLimit
        cache.countLimit = 240
        metadataCache.countLimit = 512
    }

    public func clearCache() {
        cache.removeAllObjects()
        metadataCache.removeAllObjects()
    }

    /// Returns a cached image without triggering a decode.
    public func cachedImage(for url: URL, maxPixel: Int, allowEmbedded: Bool = true) -> CGImage? {
        let target = max(32, maxPixel)
        let key = cacheKey(url: url, maxPixel: target, variant: allowEmbedded ? "preview" : "fit")
        return cache.object(forKey: key)?.image
    }

    /// Loads a display-sized image. `allowEmbedded` should be true for the first
    /// quick frame (JPEG/HEIC often have an embedded thumbnail) and false for the
    /// sharp fit-to-window pass.
    public func image(for url: URL, maxPixel: Int, allowEmbedded: Bool = true) -> CGImage? {
        let target = max(32, maxPixel)
        let key = cacheKey(url: url, maxPixel: target, variant: allowEmbedded ? "preview" : "fit")
        if let box = cache.object(forKey: key) {
            return box.image
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if allowEmbedded {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        }

        let image: CGImage?
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            image = thumbnail
        } else if let full = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = downsample(full, maxPixel: target)
        } else {
            image = nil
        }

        guard let image else { return nil }
        let cost = max(1, image.bytesPerRow * image.height)
        cache.setObject(CGImageBox(image), forKey: key, cost: cost)
        return image
    }

    /// Returns only the embedded preview, without decoding the full image.
    /// Returns nil quickly when the file has no embedded thumbnail (common for PNG).
    public func embeddedThumbnail(for url: URL, maxPixel: Int = 512) -> CGImage? {
        let target = max(32, maxPixel)
        let key = cacheKey(url: url, maxPixel: target, variant: "embedded")
        if let box = cache.object(forKey: key) { return box.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let cost = max(1, image.bytesPerRow * image.height)
        cache.setObject(CGImageBox(image), forKey: key, cost: cost)
        return image
    }

    public func metadata(for url: URL) -> ImageMetadata? {
        let key = url.path as NSString
        if let box = metadataCache.object(forKey: key) {
            return box.metadata
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]

        let width = integer(properties[kCGImagePropertyPixelWidth]) ?? 0
        let height = integer(properties[kCGImagePropertyPixelHeight]) ?? 0
        let fileSize: Int64
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSize = Int64(size)
        } else if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber {
            fileSize = size.int64Value
        } else {
            fileSize = 0
        }

        let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any]
        let iso = isoValues?.first.flatMap(integer)

        let metadata = ImageMetadata(
            pixelWidth: width,
            pixelHeight: height,
            fileSize: fileSize,
            colorModel: string(properties[kCGImagePropertyColorModel]),
            dpiWidth: number(properties[kCGImagePropertyDPIWidth]),
            dpiHeight: number(properties[kCGImagePropertyDPIHeight]),
            cameraMake: string(tiff[kCGImagePropertyTIFFMake]),
            cameraModel: string(tiff[kCGImagePropertyTIFFModel]),
            lens: string(exif[kCGImagePropertyExifLensModel]),
            exposureTime: number(exif[kCGImagePropertyExifExposureTime]),
            fNumber: number(exif[kCGImagePropertyExifFNumber]),
            iso: iso,
            focalLength: number(exif[kCGImagePropertyExifFocalLength]),
            dateTaken: string(exif[kCGImagePropertyExifDateTimeOriginal])
                ?? string(tiff[kCGImagePropertyTIFFDateTime]),
            orientation: integer(properties[kCGImagePropertyOrientation]) ?? 1
        )

        metadataCache.setObject(MetadataBox(metadata), forKey: key)
        return metadata
    }

    public func dimensions(for url: URL) -> CGSize? {
        guard let metadata = metadata(for: url), metadata.pixelWidth > 0, metadata.pixelHeight > 0 else {
            return nil
        }
        return metadata.pixelSize
    }

    private func cacheKey(url: URL, maxPixel: Int, variant: String) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(maxPixel)|\(variant)|\(stamp)|\(size)" as NSString
    }

    private func downsample(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let scale = min(1.0, CGFloat(maxPixel) / CGFloat(max(width, height)))
        if scale >= 1.0 { return image }
        let newWidth = max(1, Int(CGFloat(width) * scale))
        let newHeight = max(1, Int(CGFloat(height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let alpha = image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: alpha
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    private func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return nil
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let string = value as? NSString, string.length > 0 { return string as String }
        return nil
    }
}
