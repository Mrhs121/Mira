import Foundation

public struct ImageItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let fileName: String
    public let fileSize: Int64
    public let modificationDate: Date

    public var id: URL { url }

    public init(url: URL, fileName: String, fileSize: Int64, modificationDate: Date) {
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}
