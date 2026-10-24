import Foundation
import CoreGraphics

public struct ImageMetadata: Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64
    public let colorModel: String?
    public let dpiWidth: Double?
    public let dpiHeight: Double?
    public let cameraMake: String?
    public let cameraModel: String?
    public let lens: String?
    public let exposureTime: Double?
    public let fNumber: Double?
    public let iso: Int?
    public let focalLength: Double?
    public let dateTaken: String?
    public let orientation: Int

    public var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    public var megapixels: Double {
        Double(pixelWidth) * Double(pixelHeight) / 1_000_000.0
    }
}
