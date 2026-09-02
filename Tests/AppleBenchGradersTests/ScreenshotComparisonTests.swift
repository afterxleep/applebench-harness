import AppleBenchCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AppleBenchGraders

@Suite("Screenshot comparison")
struct ScreenshotComparisonTests {
    /// Writes a solid-colour PNG, standing in for a rendered screen.
    private func png(red: Int, green: Int, blue: Int, named name: String) throws -> URL {
        let edge = 64
        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = UInt8(red)
            pixels[index + 1] = UInt8(green)
            pixels[index + 2] = UInt8(blue)
            pixels[index + 3] = 255
        }
        let context = CGContext(
            data: &pixels,
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            bytesPerRow: edge * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString).png")
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    @Test("Identical renderings differ by nothing")
    func identical() throws {
        let light = try png(red: 250, green: 250, blue: 250, named: "light")
        let same = try png(red: 250, green: 250, blue: 250, named: "same")
        defer { try? FileManager.default.removeItem(at: light); try? FileManager.default.removeItem(at: same) }
        #expect(try ScreenshotComparison.difference(light, same) < 0.001)
    }

    @Test("A screen that adapts to dark mode differs substantially")
    func lightAgainstDark() throws {
        // The whole check: near-white against near-black is what a screen
        // reading semantic colours does, and a hardcoded one does not.
        let light = try png(red: 250, green: 250, blue: 250, named: "light")
        let dark = try png(red: 20, green: 20, blue: 20, named: "dark")
        defer { try? FileManager.default.removeItem(at: light); try? FileManager.default.removeItem(at: dark) }
        #expect(try ScreenshotComparison.difference(light, dark) > 0.5)
    }

    @Test("A small colour shift is not mistaken for adapting")
    func nearlyIdentical() throws {
        let first = try png(red: 250, green: 250, blue: 250, named: "a")
        let second = try png(red: 247, green: 248, blue: 250, named: "b")
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let difference = try ScreenshotComparison.difference(first, second)
        #expect(difference > 0)
        #expect(difference < 0.02)
    }

    @Test("A missing screenshot is an error, never a passing comparison")
    func missingFile() {
        let absent = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).png")
        #expect(throws: BenchmarkFailure.self) {
            _ = try ScreenshotComparison.difference(absent, absent)
        }
    }
}
