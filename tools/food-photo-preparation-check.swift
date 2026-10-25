// Compile with the real FoodPhotoPreparation.swift and the built REPickShared module.
import Foundation
import ImageIO
import REPickShared
import UniformTypeIdentifiers

@main
enum FoodPhotoPreparationCheck {
    private enum CheckFailure: Error { case failed(String) }

    private struct Checks {
        var count = 0

        mutating func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw CheckFailure.failed(message) }
            count += 1
        }

        mutating func rejects(_ expected: FoodPhotoError, _ operation: () throws -> Void) throws {
            do {
                try operation()
                throw CheckFailure.failed("Expected rejection: \(expected)")
            } catch let error as FoodPhotoError {
                let matches: Bool
                switch (error, expected) {
                case (.invalidImage, .invalidImage), (.imageTooLarge, .imageTooLarge),
                     (.invalidDimensions, .invalidDimensions): matches = true
                default: matches = false
                }
                try require(matches, "Unexpected rejection: \(error); expected \(expected)")
            }
        }
    }

    static func main() async throws {
        var checks = Checks()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repick-photo-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = try quadrants(width: 2_400, height: 1_200)
        // Samples are top-left, top-right, bottom-left and bottom-right in decoded row order.
        let orientationCases: [(Int, Int, Int, [String])] = [
            (1, 1_280, 640, ["red", "green", "blue", "yellow"]),
            (2, 1_280, 640, ["green", "red", "yellow", "blue"]),
            (3, 1_280, 640, ["yellow", "blue", "green", "red"]),
            (6, 640, 1_280, ["blue", "red", "yellow", "green"]),
            (8, 640, 1_280, ["green", "yellow", "red", "blue"]),
        ]
        var fixture = Data()
        for (orientation, width, height, expectedColors) in orientationCases {
            let input = try encode(image, type: .jpeg, properties: [
                kCGImagePropertyOrientation: orientation,
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 37.5,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 127.0,
                    kCGImagePropertyGPSLongitudeRef: "E",
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05",
                    kCGImagePropertyExifLensModel: "Synthetic private lens",
                    kCGImagePropertyExifUserComment: "Synthetic private comment",
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFImageDescription: "Synthetic private caption",
                    kCGImagePropertyTIFFMake: "Synthetic private camera",
                    kCGImagePropertyTIFFModel: "Synthetic camera model",
                ],
            ])
            if orientation == 1 { fixture = input }
            let sourceProperties = try properties(input)
            try checks.require(sourceProperties[kCGImagePropertyGPSDictionary] != nil, "Fixture GPS missing")
            let sourceExif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            try checks.require(sourceExif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:01:02 03:04:05"
                               && sourceExif?[kCGImagePropertyExifLensModel] as? String == "Synthetic private lens"
                               && sourceExif?[kCGImagePropertyExifUserComment] as? String == "Synthetic private comment",
                               "Fixture private EXIF missing")
            let sourceTIFF = sourceProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            try checks.require(sourceTIFF?[kCGImagePropertyTIFFImageDescription] as? String == "Synthetic private caption"
                               && sourceTIFF?[kCGImagePropertyTIFFMake] as? String == "Synthetic private camera"
                               && sourceTIFF?[kCGImagePropertyTIFFModel] as? String == "Synthetic camera model",
                               "Fixture private TIFF missing")

            let photo = try FoodPhotoPreparation.prepare(data: input)
            let output = try properties(photo.jpegData)
            try checks.require((output[kCGImagePropertyPixelWidth] as? Int) == width, "Orientation \(orientation) width")
            try checks.require((output[kCGImagePropertyPixelHeight] as? Int) == height, "Orientation \(orientation) height")
            let outputOrientation = output[kCGImagePropertyOrientation] as? Int
            try checks.require(outputOrientation == nil || outputOrientation == 1, "Orientation was not normalized")
            try checks.require(output[kCGImagePropertyGPSDictionary] == nil, "GPS leaked")
            // ImageIO adds fresh color-space and pixel-size tags to JPEGs without retaining source metadata.
            let exif = output[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let allowedExifKeys: Set<CFString> = [kCGImagePropertyExifColorSpace,
                                                kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension]
            try checks.require(Set(exif.keys).isSubset(of: allowedExifKeys), "Source EXIF leaked")
            let tiff = output[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            let allowedTIFFKeys: Set<CFString> = [kCGImagePropertyTIFFXResolution,
                                                kCGImagePropertyTIFFYResolution, kCGImagePropertyTIFFResolutionUnit]
            try checks.require(Set(tiff.keys).isSubset(of: allowedTIFFKeys), "Source TIFF leaked")
            try checks.require(photo.jpegData.count <= FoodPhotoAnalysisRequest.Image.maximumBytes, "JPEG exceeds 2 MiB")
            try checks.require(try quadrantColors(photo.jpegData) == expectedColors, "Orientation \(orientation) pixel positions")

            let request = try photo.request
            try request.validate()
            let json = try HealthReportCoding.encoder().encode(request)
            try checks.require(json.count <= 2_900_000, "Encoded request exceeds the HTTP body bound")
            try checks.require(request.image.mimeType == "image/jpeg", "Incorrect upload MIME type")
            try checks.require(Data(base64Encoded: request.image.base64) == photo.jpegData, "Upload bytes changed")
            let decoded = try HealthReportCoding.decoder().decode(FoodPhotoAnalysisRequest.self, from: json)
            try decoded.validate()
            try checks.require(decoded == request, "Request JSON roundtrip failed")
        }

        let transparent = try transparentImage()
        let png = try encode(transparent, type: .png)
        let pngPhoto = try FoodPhotoPreparation.prepare(data: png)
        try checks.require(try quadrantColors(pngPhoto.jpegData) == ["white", "red", "white", "red"],
                           "Transparent pixels must be white, and opaque colors preserved")
        try checks.require(try properties(pngPhoto.jpegData)[kCGImagePropertyPixelWidth] as? Int == 100,
                           "Small images must not be enlarged")

        try checks.rejects(.invalidImage) { _ = try FoodPhotoPreparation.prepare(data: Data()) }
        try checks.rejects(.invalidImage) { _ = try FoodPhotoPreparation.prepare(data: Data("not an image".utf8)) }
        try checks.rejects(.invalidImage) { _ = try FoodPhotoPreparation.prepare(data: Data(fixture.prefix(12))) }
        try checks.rejects(.imageTooLarge) {
            _ = try FoodPhotoPreparation.prepare(data: Data(count: FoodPhotoPreparation.maximumImportBytes + 1))
        }
        let wide = try encode(try quadrants(width: 20_001, height: 1), type: .png)
        try checks.rejects(.invalidDimensions) { _ = try FoodPhotoPreparation.prepare(data: wide) }
        let tall = try encode(try quadrants(width: 1, height: 20_001), type: .png)
        try checks.rejects(.invalidDimensions) { _ = try FoodPhotoPreparation.prepare(data: tall) }

        let fileURL = directory.appendingPathComponent("fixture.jpg")
        try fixture.write(to: fileURL)
        let filePhoto = try FoodPhotoPreparation.prepare(fileURL: fileURL)
        try checks.require(filePhoto.jpegData == FoodPhotoPreparation.prepare(data: fixture).jpegData,
                           "File and data paths must prepare identical pixels")
        try checks.rejects(.invalidImage) { _ = try FoodPhotoPreparation.prepare(fileURL: directory) }
        guard let remoteURL = URL(string: "https://example.invalid/photo.jpg") else {
            throw CheckFailure.failed("Could not construct non-file URL fixture")
        }
        try checks.rejects(.invalidImage) {
            _ = try FoodPhotoPreparation.prepare(fileURL: remoteURL)
        }
        let emptyURL = directory.appendingPathComponent("empty.jpg")
        try Data().write(to: emptyURL)
        try checks.rejects(.invalidImage) { _ = try FoodPhotoPreparation.prepare(fileURL: emptyURL) }
        let oversizedURL = directory.appendingPathComponent("oversized.jpg")
        try Data().write(to: oversizedURL)
        let oversizedFile = try FileHandle(forWritingTo: oversizedURL)
        try oversizedFile.truncate(atOffset: UInt64(FoodPhotoPreparation.maximumImportBytes + 1))
        try oversizedFile.close()
        try checks.rejects(.imageTooLarge) { _ = try FoodPhotoPreparation.prepare(fileURL: oversizedURL) }

        let dataCancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try FoodPhotoPreparation.prepare(data: fixture); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        try checks.require(dataCancelled, "Data preparation ignored cancellation")
        let fileCancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try FoodPhotoPreparation.prepare(fileURL: fileURL); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        try checks.require(fileCancelled, "File preparation ignored cancellation")
        print("Food photo preparation: \(checks.count) checks passed; orientation, metadata, PNG compositing, bounds, request and cancellation.")
    }

    private static func quadrants(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
        for y in 0..<height {
            for x in 0..<width {
                let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
                let index = (y * width + x) * 4
                bytes[index] = color[0]
                bytes[index + 1] = color[1]
                bytes[index + 2] = color[2]
            }
        }
        return try makeImage(bytes: bytes, width: width, height: height)
    }

    private static func transparentImage() throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: 100 * 100 * 4)
        for y in 0..<100 {
            for x in 50..<100 {
                bytes[(y * 100 + x) * 4] = 255
                bytes[(y * 100 + x) * 4 + 3] = 255
            }
        }
        return try makeImage(bytes: bytes, width: 100, height: 100)
    }

    private static func makeImage(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                                      .union(.byteOrder32Big),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CheckFailure.failed("Could not create image fixture")
        }
        return image
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw CheckFailure.failed("Could not create fixture destination")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CheckFailure.failed("Could not encode fixture") }
        return data as Data
    }

    private static func properties(_ data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let result = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw CheckFailure.failed("Could not read image properties")
        }
        return result
    }

    private static func quadrantColors(_ data: Data) throws -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw CheckFailure.failed("Could not decode output pixels")
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw CheckFailure.failed("Could not sample output pixels")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return [(1, 1), (3, 1), (1, 3), (3, 3)].map { x, y in
                let index = ((image.height * y / 4) * image.width + image.width * x / 4) * 4
                let r = buffer[index], g = buffer[index + 1], b = buffer[index + 2]
                if r > 230, g > 230, b > 230 { return "white" }
                if r > 200, g < 40, b < 40 { return "red" }
                if g > 200, r < 40, b < 40 { return "green" }
                if b > 200, r < 40, g < 40 { return "blue" }
                if r > 200, g > 200, b < 40 { return "yellow" }
                return "unexpected(\(r),\(g),\(b))"
            }
        }
    }
}
