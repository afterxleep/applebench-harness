import AppleBenchCore
import CoreGraphics
import Foundation
import ImageIO

/// How different two screenshots are, as a fraction from 0 to 1.
///
/// Colour is the one thing the accessibility tree cannot report, which is why
/// dark mode, contrast and tinting were ungradeable here until now. The check
/// this enables does not need a reference image or a tolerance anyone has to
/// tune: a screen that adapts **looks different** in light and dark, and a
/// screen with its colours hardcoded looks identical. The question is whether
/// the two renderings differ at all, not whether either matches a golden file.
///
/// Both images are reduced to a small fixed grid before comparing, so the
/// answer is about the picture rather than about antialiasing, and a one-pixel
/// cursor blink cannot register as a change.
enum ScreenshotComparison {
    /// Edge of the grid both images are reduced to.
    static let sampleEdge = 32

    /// Mean absolute per-channel difference, 0 (identical) to 1 (inverted).
    static func difference(_ first: URL, _ second: URL) throws -> Double {
        let a = try samples(of: first)
        let b = try samples(of: second)
        guard a.count == b.count, !a.isEmpty else {
            throw BenchmarkFailure.graderFailure(
                grader: "uiflow",
                message: "Screenshots could not be compared: sampled \(a.count) and \(b.count) values"
            )
        }
        var total = 0
        for index in a.indices {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count * 255)
    }

    /// Draws the image into a fixed-size RGB grid and returns the raw channels.
    static func samples(of url: URL) throws -> [UInt8] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw BenchmarkFailure.graderFailure(
                grader: "uiflow",
                message: "Could not read the screenshot at \(url.lastPathComponent)"
            )
        }
        let edge = sampleEdge
        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
        guard let context = CGContext(
            data: &pixels,
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            bytesPerRow: edge * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BenchmarkFailure.graderFailure(
                grader: "uiflow",
                message: "Could not create a bitmap to compare screenshots in"
            )
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))

        // Alpha is dropped: a screenshot is opaque, and premultiplied alpha
        // would let a fully transparent corner read as a colour change.
        var channels: [UInt8] = []
        channels.reserveCapacity(edge * edge * 3)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            channels.append(pixels[index])
            channels.append(pixels[index + 1])
            channels.append(pixels[index + 2])
        }
        return channels
    }
}
