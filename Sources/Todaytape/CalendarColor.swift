import AppKit
import SwiftUI

/// Opaque sRGB colours persist independently of Google's calendar colours.
struct CalendarColor: Equatable {
    let hex: String

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        self.hex = value.uppercased()
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(hex: String(format: "%02X%02X%02X",
            Int((min(1, max(0, rgb.redComponent)) * 255).rounded()),
            Int((min(1, max(0, rgb.greenComponent)) * 255).rounded()),
            Int((min(1, max(0, rgb.blueComponent)) * 255).rounded())))
    }

    var color: Color { Color(hex: hex) }

    private var components: [Double] {
        let value = UInt32(hex, radix: 16)!
        return [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
    }

    var luminance: Double {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    /// Keep small titles and times readable, including on arbitrary custom colours.
    var foreground: Color { usesWhiteText ? .white : .black }
    var usesWhiteText: Bool { 1.05 / (luminance + 0.05) >= (luminance + 0.05) / 0.05 }
    var textContrast: Double { max(1.05 / (luminance + 0.05), (luminance + 0.05) / 0.05) }

    func block(past: Bool) -> CalendarColor {
        guard past else { return self }

        // Calibrated from the original #3896E8 → #9EC8EF pair in HSL:
        // move lightness 109/222 of the remaining distance to white, and
        // retain (81/113)/(176/222) of the saturation. Preserve hue exactly
        // (the original pair differs by 0.93°), giving #9EC9EF for that blue.
        // Use the same rule in both themes and keep the fill opaque so text
        // contrast is calculated against the colour actually displayed.
        let rgb = components
        let maximum = rgb.max()!
        let minimum = rgb.min()!
        let chroma = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        var hue: Double = 0 // In sixths of a turn, [0, 6).
        if chroma > 0 {
            if maximum == rgb[0] {
                hue = (rgb[1] - rgb[2]) / chroma
                if hue < 0 { hue += 6 }
            } else if maximum == rgb[1] {
                hue = (rgb[2] - rgb[0]) / chroma + 2
            } else {
                hue = (rgb[0] - rgb[1]) / chroma + 4
            }
        }

        let fadedLightness = lightness + (1 - lightness) * (109.0 / 222.0)
        let fadedSaturation = saturation * ((81.0 / 113.0) / (176.0 / 222.0))
        let c = (1 - abs(2 * fadedLightness - 1)) * fadedSaturation
        let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let m = fadedLightness - c / 2
        let channels: [Double]
        switch hue {
        case ..<1: channels = [c, x, 0]
        case ..<2: channels = [x, c, 0]
        case ..<3: channels = [0, c, x]
        case ..<4: channels = [0, x, c]
        case ..<5: channels = [x, 0, c]
        default: channels = [c, 0, x]
        }
        let bytes = channels.map { Int((min(1, max(0, $0 + m)) * 255).rounded()) }
        return CalendarColor(hex: String(format: "%02X%02X%02X", bytes[0], bytes[1], bytes[2]))!
    }
}

enum CalendarPalette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
        var value: CalendarColor { CalendarColor(hex: hex)! }
    }

    // Moderate saturation, separated hues; bright red stays reserved for “now”.
    static let swatches = [
        Swatch(name: "Blue", hex: "6FA8DC"),
        Swatch(name: "Teal", hex: "65B8A6"),
        Swatch(name: "Amber", hex: "DEB568"),
        Swatch(name: "Violet", hex: "A995D0"),
        Swatch(name: "Rose", hex: "D994AC"),
        Swatch(name: "Olive", hex: "A8B879")
    ]
    static var fallback: CalendarColor { swatches[0].value }
}
