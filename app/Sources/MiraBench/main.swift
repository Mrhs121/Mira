import Foundation
import MiraCore

func format(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func measure<T>(_ body: () -> T) -> (T, TimeInterval) {
    let start = CFAbsoluteTimeGetCurrent()
    let value = body()
    return (value, CFAbsoluteTimeGetCurrent() - start)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("用法: mira-bench <图片路径> [最大像素，默认 2400]\n", stderr)
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])
let maxPixel = arguments.count >= 3 ? (Int(arguments[2]) ?? 2400) : 2400
let pipeline = ImagePipeline(memoryLimit: 128 * 1024 * 1024)

let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
print("文件: \(url.lastPathComponent)")
print("大小: \(format(fileSize))")
print("目标: \(maxPixel)px")

let (metadata, metadataTime) = measure { pipeline.metadata(for: url) }
if let metadata {
    print(String(format: "尺寸: %d × %d (%.1f MP)", metadata.pixelWidth, metadata.pixelHeight, metadata.megapixels))
    print("元数据: \(String(format: "%.1f", metadataTime * 1000))ms")
} else {
    print("元数据: 读取失败")
}

pipeline.clearCache()
let (placeholder, placeholderTime) = measure {
    pipeline.image(for: url, maxPixel: 512, allowEmbedded: true)
}
if let placeholder {
    print(String(format: "首帧 512px: %.1fms (%d × %d)", placeholderTime * 1000, placeholder.width, placeholder.height))
} else {
    print("首帧: 失败")
}

let (embedded, embeddedTime) = measure {
    pipeline.embeddedThumbnail(for: url, maxPixel: 512)
}
if let embedded {
    print(String(format: "内嵌预览: %.1fms (%d × %d)", embeddedTime * 1000, embedded.width, embedded.height))
} else {
    print(String(format: "内嵌预览: 无 (%.1fms)", embeddedTime * 1000))
}

pipeline.clearCache()
let (fit, fitTime) = measure {
    pipeline.image(for: url, maxPixel: maxPixel, allowEmbedded: false)
}
if let fit {
    print(String(format: "适合窗口 %dpx: %.1fms (%d × %d)", maxPixel, fitTime * 1000, fit.width, fit.height))
} else {
    print("适合窗口: 失败")
}

let (_, cachedTime) = measure {
    _ = pipeline.image(for: url, maxPixel: maxPixel, allowEmbedded: false)
}
print(String(format: "缓存命中: %.3fms", cachedTime * 1000))
