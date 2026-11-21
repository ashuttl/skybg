import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture in the making: sRGB as floats, three to a pixel, top row first.
public struct Canvas {
    public let width: Int, height: Int
    public var data: [Float]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        data = [Float](repeating: 0, count: width * height * 3)
    }

    /// Paint every row, several at a time. `body` is given the row's index
    /// and its pixels.
    public mutating func fillRows(_ body: (_ y: Int, _ row: UnsafeMutablePointer<Float>) -> Void) {
        let width = width, height = height
        data.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                body(y, base + y * width * 3)
            }
        }
    }

    /// Paint every pixel from its place on the screen, as fractions of the
    /// width and height at the pixel's centre.
    public mutating func fill(_ color: (_ x: Double, _ y: Double) -> V3) {
        let width = width, height = height
        fillRows { y, row in
            let fy = (Double(y) + 0.5) / Double(height)
            for x in 0..<width {
                row.put(x, color((Double(x) + 0.5) / Double(width), fy))
            }
        }
    }

    /// Enlarged with the Mitchell filter, as ImageMagick enlarges.
    public func resized(width newWidth: Int, height newHeight: Int) -> Canvas {
        func taps(_ from: Int, _ to: Int) -> [(index: [Int], weight: [Float])] {
            (0..<to).map { k in
                let at = (Double(k) + 0.5) * Double(from) / Double(to) - 0.5
                let first = Int(floor(at)) - 1
                var weights = (0..<4).map { mitchell(at - Double(first + $0)) }
                let total = weights.reduce(0, +)
                weights = weights.map { $0 / total }
                return ((0..<4).map { min(max(first + $0, 0), from - 1) }, weights.map(Float.init))
            }
        }
        let across = taps(width, newWidth), down = taps(height, newHeight)
        var wide = Canvas(width: newWidth, height: height)
        data.withUnsafeBufferPointer { source in
            wide.fillRows { y, row in
                for x in 0..<newWidth {
                    let tap = across[x]
                    for channel in 0..<3 {
                        var sum: Float = 0
                        for k in 0..<4 { sum += source[(y * width + tap.index[k]) * 3 + channel] * tap.weight[k] }
                        row[x * 3 + channel] = sum
                    }
                }
            }
        }
        var out = Canvas(width: newWidth, height: newHeight)
        wide.data.withUnsafeBufferPointer { source in
            out.fillRows { y, row in
                let tap = down[y]
                for i in 0..<(newWidth * 3) {
                    var sum: Float = 0
                    for k in 0..<4 { sum += source[tap.index[k] * newWidth * 3 + i] * tap.weight[k] }
                    row[i] = sum
                }
            }
        }
        return out
    }
}

private func mitchell(_ x: Double) -> Double {
    let x = abs(x)
    if x < 1 { return (7 * x * x * x - 12 * x * x + 16.0 / 3) / 6 }
    if x < 2 { return (-7.0 / 3 * x * x * x + 12 * x * x - 20 * x + 32.0 / 3) / 6 }
    return 0
}

extension UnsafeMutablePointer where Pointee == Float {
    @inline(__always) func put(_ x: Int, _ color: V3) {
        self[3 * x] = Float(color.x)
        self[3 * x + 1] = Float(color.y)
        self[3 * x + 2] = Float(color.z)
    }
}

/// Where a fraction `s` of the screen falls on a grid of `count` cells whose
/// first and last cells stand for 0 and 1 — the grids bin/skybg enlarges.
@inlinable func gridParameter(_ s: Double, _ count: Int) -> Double {
    clamp((s * Double(count) - 0.5) / Double(count - 1))
}

/// A finished picture: eight bits a channel, ready to draw on and to save.
public final class Bitmap {
    public let width: Int, height: Int
    public var bytes: [UInt8]   // RGBX, top row first

    /// The grain that goes in with the rounding to eight bits: the standard
    /// deviation, of 1, of the noise in each channel. It keeps a slow
    /// gradient from banding and gives the picture a tooth. Measured from
    /// what ImageMagick's `-attenuate 0.25 +noise Gaussian` adds: five levels.
    public static let grain = 5.0 / 255

    public init(_ canvas: Canvas, grain: Double = Bitmap.grain) {
        width = canvas.width
        height = canvas.height
        bytes = [UInt8](repeating: 255, count: width * height * 4)
        let width = width, seed = UInt64.random(in: 0 ... .max)
        let scale = Float(grain * 255)
        canvas.data.withUnsafeBufferPointer { source in
            bytes.withUnsafeMutableBufferPointer { out in
                let outBase = out.baseAddress!
                DispatchQueue.concurrentPerform(iterations: canvas.height) { y in
                    var dice = Dice(seed: seed, row: y)
                    for x in 0..<width {
                        let i = y * width + x
                        for channel in 0..<3 {
                            var value = source[i * 3 + channel] * 255
                            if scale > 0 { value += dice.roll() * scale }
                            outBase[i * 4 + channel] = UInt8(max(0, min(255, value.rounded())))
                        }
                    }
                }
            }
        }
    }

    /// Grain over a picture already drawn on, for the styles whose drawing
    /// is part of the print.
    public func addGrain(_ grain: Double = Bitmap.grain) {
        if grain <= 0 { return }
        let width = width, seed = UInt64.random(in: 0 ... .max)
        let scale = Float(grain * 255)
        bytes.withUnsafeMutableBufferPointer { out in
            let outBase = out.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                var dice = Dice(seed: seed, row: y)
                for i in (y * width * 4)..<((y + 1) * width * 4) where i % 4 != 3 {
                    outBase[i] = UInt8(max(0, min(255, (Float(outBase[i]) + dice.roll() * scale).rounded())))
                }
            }
        }
    }

    /// Draw on the picture. The context's origin is the centre of the top
    /// left pixel, with y running down the screen, as in ImageMagick.
    public func draw(_ body: (CGContext) -> Void) {
        let width = width, height = height
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0.5, y: 0.5)
            body(context)
        }
    }

    /// Lay a drawing over the picture through a veil: `veil` gives, for each
    /// row, how much of the drawing shows there.
    public func drawVeiled(_ veil: (_ y: Double) -> Double, _ body: (CGContext) -> Void) {
        let width = width, height = height
        var layer = [UInt8](repeating: 0, count: width * height * 4)
        layer.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0.5, y: 0.5)
            body(context)
        }
        for y in 0..<height {
            let show = veil((Double(y) + 0.5) / Double(height))
            if show <= 0 { continue }
            for x in 0..<width {
                let i = (y * width + x) * 4
                let alpha = Double(layer[i + 3]) / 255
                if alpha == 0 { continue }
                for channel in 0..<3 {
                    let under = Double(bytes[i + channel]) * (1 - alpha * show)
                    bytes[i + channel] = UInt8(min(255, (under + Double(layer[i + channel]) * show).rounded()))
                }
            }
        }
    }

    public func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Write a PNG beside `url` and move it into place, so a reader never
    /// sees half a file.
    public func writePNG(to url: URL) throws {
        let temporary = url.appendingPathExtension("tmp")
        guard let image = cgImage(),
              let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SkyError("could not write \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SkyError("could not write \(url.path)") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}

/// Noise for the grain: near enough a bell curve of unit spread, and cheap.
struct Dice {
    var state: UInt64

    /// Each row has its own scrambled seed; rows seeded a step apart would
    /// repeat one another, a step along.
    init(seed: UInt64, row: Int) {
        state = (seed ^ UInt64(row)) &* 0xD1B54A32D192ED03
        state = (state ^ (state >> 32)) &* 0xBF58476D1CE4E5B9
    }

    @inline(__always) mutating func roll() -> Float {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        // Four dice make a fair bell curve.
        let sum = (z & 0xFFFF) + ((z >> 16) & 0xFFFF) + ((z >> 32) & 0xFFFF) + (z >> 48)
        return (Float(sum) - 131070) * (1.7320508 / 65535)
    }
}

/// An expected, actionable failure.
public struct SkyError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

extension CGContext {
    func fill(_ color: V3, _ alpha: Double) {
        setFillColor(CGColor(srgbRed: clamp(color.x), green: clamp(color.y), blue: clamp(color.z), alpha: alpha))
    }

    func stroke(_ color: V3, _ alpha: Double) {
        setStrokeColor(CGColor(srgbRed: clamp(color.x), green: clamp(color.y), blue: clamp(color.z), alpha: alpha))
    }

    /// A filled circle, as ImageMagick fills one: about a third of a pixel
    /// fatter than asked. It hardly shows on a sun, but it doubles the light
    /// of a faint star, and the styles were tuned with it.
    func disc(_ x: Double, _ y: Double, _ radius: Double) {
        let radius = radius + 0.35
        fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }

    func ring(_ x: Double, _ y: Double, _ radius: Double) {
        strokeEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }

    func polygon(_ points: [(Double, Double)]) {
        guard let first = points.first else { return }
        beginPath()
        move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { addLine(to: CGPoint(x: point.0, y: point.1)) }
        closePath()
        fillPath()
    }
}
