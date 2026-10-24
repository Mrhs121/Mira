import Foundation
import UniformTypeIdentifiers

public enum ImageSort: String, CaseIterable, Sendable {
    case name
    case date
    case size

    public var title: String {
        switch self {
        case .name: return "名称"
        case .date: return "修改时间"
        case .size: return "大小"
        }
    }
}

public enum FolderScanner {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
        "tif", "tiff", "bmp", "avif", "ico", "psd"
    ]

    public static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    public static func scan(
        folder: URL,
        sort: ImageSort = .name,
        ascending: Bool = true
    ) throws -> [ImageItem] {
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var items: [ImageItem] = []
        items.reserveCapacity(urls.count)

        for url in urls {
            guard isImageFile(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let date = values.contentModificationDate ?? .distantPast
            items.append(
                ImageItem(
                    url: url,
                    fileName: url.lastPathComponent,
                    fileSize: size,
                    modificationDate: date
                )
            )
        }

        switch sort {
        case .name:
            items.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .date:
            items.sort {
                if $0.modificationDate == $1.modificationDate {
                    return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                }
                return $0.modificationDate < $1.modificationDate
            }
        case .size:
            items.sort {
                if $0.fileSize == $1.fileSize {
                    return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                }
                return $0.fileSize < $1.fileSize
            }
        }

        if !ascending {
            items.reverse()
        }
        return items
    }

    public static func scanAsync(
        folder: URL,
        sort: ImageSort = .name,
        ascending: Bool = true
    ) async throws -> [ImageItem] {
        try await Task.detached(priority: .userInitiated) {
            try scan(folder: folder, sort: sort, ascending: ascending)
        }.value
    }
}
