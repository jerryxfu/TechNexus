import SwiftUI
import UIKit

/// Hex encoding for `Color`, in the app target.
///
/// The extension has its own `LiveActivityFormat.color(hex:)` and cannot use
/// this one. It doesn't link ComposeApp and is a separate target. That
/// duplication is the same trade already documented for status colours: two
/// copies, both of which must change together. TODO: can we merge both implementations
///
/// Within the app target there is exactly one copy, and this is it.
/// `ScheduleLiveActivityManager` encodes highlight colours for the Live Activity
/// payload, and `HighlightedTeamsStore` encodes the same colours for disk. They
/// must agree, so they call the same function.
enum ColorHex {
    /// `#RRGGBB`. Falls back to yellow's hex if the colour can't be resolved to
    /// RGB. a pattern colour or a dynamic one with no trait context.
    static func string(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return fallbackHex
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }

    /// Accepts `#RRGGBB` or `RRGGBB`. Returns nil rather than a default so
    /// callers can decide whether a bad value means "drop this entry" or
    /// "substitute something"; the disk store wants the former, the Live Activity the latter.
    static func color(from hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return nil
        }

        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static let fallbackHex = "#FFFF00"
}
