import Foundation

/// A colour (sRGB or Oklab) or a direction.
public typealias V3 = SIMD3<Double>

@inlinable public func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    max(lo, min(hi, v))
}

@inlinable public func smoothstep(_ lo: Double, _ hi: Double, _ v: Double) -> Double {
    let t = clamp((v - lo) / (hi - lo))
    return t * t * (3 - 2 * t)
}

@inlinable public func lerp(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
@inlinable public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// The remainder that is never negative, as Python's `%` is.
@inlinable public func pmod(_ a: Double, _ n: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: n)
    return r < 0 ? r + n : r
}

@inlinable public func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
@inlinable public func deg(_ radians: Double) -> Double { radians * 180 / .pi }

public func lighten(_ c: V3, _ t: Double) -> V3 { lerp(c, V3(1, 1, 1), t) }

public func grayOf(_ c: V3) -> V3 {
    let y = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    return V3(y, y, y)
}

public func hexrgb(_ s: String) -> V3 {
    let value = UInt32(s.hasPrefix("#") ? String(s.dropFirst()) : s, radix: 16) ?? 0
    return V3(Double((value >> 16) & 0xff), Double((value >> 8) & 0xff), Double(value & 0xff)) / 255
}

// MARK: - curves

/// Shape-preserving tangent between two secants: no overshoot.
public func pchipSlope(_ d0: Double, _ d1: Double, _ h0: Double, _ h1: Double) -> Double {
    if d0 * d1 <= 0 { return 0 }
    let w1 = 2 * h1 + h0, w2 = h1 + 2 * h0
    return (w1 + w2) / (w1 / d0 + w2 / d1)
}

public func hermite(_ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double, _ h: Double, _ u: Double) -> Double {
    let u2 = u * u, u3 = u2 * u
    return (2 * u3 - 3 * u2 + 1) * y0 + (u3 - 2 * u2 + u) * h * m0
        + (-2 * u3 + 3 * u2) * y1 + (u3 - u2) * h * m1
}

/// The four knots around `x` on a 24-hour circle, as (index, hour) pairs
/// whose hours run on past 0 and 24 where the circle wraps.
public func periodicKnots(_ xs: [Double], _ x: Double) -> [(index: Int, hour: Double)] {
    let count = xs.count
    let following = xs.firstIndex(where: { $0 > x }) ?? count
    let i = following - 1
    return [i - 1, i, i + 1, i + 2].map { k in
        let wrapped = ((k % count) + count) % count
        return (wrapped, xs[wrapped] + (k < 0 ? -24 : k >= count ? 24 : 0))
    }
}

/// A smooth curve through evenly spaced `stops` at `t` in 0..1,
/// shape-preserving, so the bands of a gradient meet without creases.
public func cubicRamp(_ stops: [V3], _ t: Double) -> V3 {
    let last = stops.count - 1
    let t = clamp(t) * Double(last)
    let i = min(Int(t), last - 1)
    let a = stops[max(i - 1, 0)], b = stops[i], c = stops[i + 1], d = stops[min(i + 2, last)]
    var out = V3()
    for k in 0..<3 {
        let rise = c[k] - b[k]
        let m0 = i > 0 ? pchipSlope(b[k] - a[k], rise, 1, 1) : rise
        let m1 = i + 1 < last ? pchipSlope(rise, d[k] - c[k], 1, 1) : rise
        out[k] = hermite(b[k], c[k], m0, m1, 1, t - Double(i))
    }
    return out
}

// MARK: - Oklab (Björn Ottosson, public domain)

/// Oklab from gamma-encoded sRGB.
public func srgbToOklab(_ rgb: V3) -> V3 {
    func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return V3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
              1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
              0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

/// Gamma-encoded sRGB from Oklab; out-of-gamut colours leave 0..1.
public func oklabToSrgb(_ lab: V3) -> V3 {
    let l0 = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
    let m0 = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
    let s0 = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
    let l = l0 * l0 * l0, m = m0 * m0 * m0, s = s0 * s0 * s0
    func encode(_ v: Double) -> Double {
        v < 0.0031308 ? 12.92 * v : 1.055 * pow(max(v, 0), 1 / 2.4) - 0.055
    }
    return V3(encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
              encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
              encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
}

public func oklabHue(_ lab: V3) -> Double { pmod(deg(atan2(lab.z, lab.y)), 360) }
