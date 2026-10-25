import CoreTransferable
import Foundation
import ImageIO
import REPickShared
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct PreparedFoodPhoto: Sendable {
    let jpegData: Data

    var request: FoodPhotoAnalysisRequest {
        get throws {
            try FoodPhotoAnalysisRequest(image: .init(mimeType: "image/jpeg", base64: jpegData.base64EncodedString()))
        }
    }
}

struct FoodPhotoImport: Transferable {
    let photo: PreparedFoodPhoto

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in
            // The picker owns this temporary URL; finish the bounded conversion before returning.
            FoodPhotoImport(photo: try FoodPhotoPreparation.prepare(fileURL: file.file))
        }
    }
}

enum FoodPhotoPreparation {
    static let maximumImportBytes = 25 * 1_024 * 1_024
    static let maximumEdge = 1_280

    static func prepare(fileURL: URL) throws -> PreparedFoodPhoto {
        try Task.checkCancellation()
        guard fileURL.isFileURL else { throw FoodPhotoError.invalidImage }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw FoodPhotoError.invalidImage
        }
        guard size <= maximumImportBytes else { throw FoodPhotoError.imageTooLarge }
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(1_048_576, maximumImportBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximumImportBytes else { throw FoodPhotoError.imageTooLarge }
        }
        return try prepare(data: data)
    }

    static func prepare(data: Data) throws -> PreparedFoodPhoto {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw FoodPhotoError.invalidImage }
        guard data.count <= maximumImportBytes else { throw FoodPhotoError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw FoodPhotoError.invalidImage }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw FoodPhotoError.invalidImage
        }
        try validateDimensions(width: width.doubleValue, height: height.doubleValue)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw FoodPhotoError.invalidImage
        }
        return try encode(thumbnail)
    }

    #if canImport(UIKit)
    @MainActor
    static func prepare(cameraImage image: UIImage) throws -> PreparedFoodPhoto {
        guard let original = image.cgImage else { throw FoodPhotoError.invalidImage }
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(image.imageOrientation)
        let width = Double(rotated ? original.height : original.width)
        let height = Double(rotated ? original.width : original.height)
        try validateDimensions(width: width, height: height)
        let factor = min(1, Double(maximumEdge) / max(width, height))
        let size = CGSize(width: max(1, floor(width * factor)), height: max(1, floor(height * factor)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let pixels = rendered.cgImage else { throw FoodPhotoError.invalidImage }
        return try encode(pixels)
    }
    #endif

    private static func validateDimensions(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 20_000, height <= 20_000, width * height <= 100_000_000 else {
            throw FoodPhotoError.invalidDimensions
        }
    }

    private static func encode(_ image: CGImage) throws -> PreparedFoodPhoto {
        try Task.checkCancellation()
        guard image.width > 0, image.height > 0, max(image.width, image.height) <= maximumEdge,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw FoodPhotoError.invalidImage
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let pixels = context.makeImage() else { throw FoodPhotoError.invalidImage }
        for quality in [0.86, 0.7, 0.5, 0.35] {
            try Task.checkCancellation()
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw FoodPhotoError.invalidImage
            }
            CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw FoodPhotoError.invalidImage }
            if output.length <= FoodPhotoAnalysisRequest.Image.maximumBytes {
                return PreparedFoodPhoto(jpegData: output as Data)
            }
        }
        throw FoodPhotoError.imageTooLarge
    }
}

enum FoodPhotoError: Error, LocalizedError, Sendable {
    case invalidImage, imageTooLarge, invalidDimensions
    case cameraUnavailable, cameraAccessDenied, cameraRestricted

    var errorDescription: String? {
        switch self {
        case .invalidImage: String(localized: "사진을 읽지 못했어요. 다른 사진을 선택하거나 다시 촬영해 주세요.")
        case .imageTooLarge: String(localized: "사진 파일이 너무 커요. 25MB 이하의 사진을 선택해 주세요.")
        case .invalidDimensions: String(localized: "사진 크기를 처리할 수 없어요. 다른 사진을 선택해 주세요.")
        case .cameraUnavailable: String(localized: "이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함에서 선택해 주세요.")
        case .cameraAccessDenied: String(localized: "카메라 접근이 꺼져 있어요. 설정에서 카메라 접근을 허용하거나 사진 보관함에서 선택해 주세요.")
        case .cameraRestricted: String(localized: "이 기기에서 카메라 사용이 제한되어 있어요. 사진 보관함에서 선택해 주세요.")
        }
    }
}
