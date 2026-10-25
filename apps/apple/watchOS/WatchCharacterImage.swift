import CoreGraphics
import UIKit

enum WatchCharacterImage {
    static func prepare(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data), let source = image.cgImage else { return nil }
        return UIImage(cgImage: cropped(source), scale: image.scale, orientation: image.imageOrientation)
    }

    static func cropped(_ source: CGImage) -> CGImage {
        let width = source.width, height = source.height
        guard (1...1_024).contains(width), (1...1_024).contains(height) else { return source }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return source }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return source }
        // Leave a small antialiasing border around ears, feet and worn accessories.
        let rect = CGRect(x: max(0, minX - 2), y: max(0, minY - 2),
                          width: min(width - 1, maxX + 2) - max(0, minX - 2) + 1,
                          height: min(height - 1, maxY + 2) - max(0, minY - 2) + 1)
        return source.cropping(to: rect) ?? source
    }
}
