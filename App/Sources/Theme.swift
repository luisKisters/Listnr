import SwiftUI

/// The design tokens of docs/mockups/kit.css, translated once. Views never invent
/// colors or sizes; the three rules live in docs/DESIGN.md.
///
/// Scheme 1 (Black · Purple) only; `data-scheme="2"` never ships.
enum Theme {
    static let bg = Color(red: 0.02, green: 0.02, blue: 0.02)                 // #050505
    static let raise = Color(red: 0.051, green: 0.051, blue: 0.051)           // #0d0d0d
    static let raise2 = Color(red: 0.086, green: 0.078, blue: 0.094)          // #161418
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.72)
    static let ink3 = Color.white.opacity(0.50)
    static let line = Color.white.opacity(0.15)
    static let line2 = Color.white.opacity(0.09)
    static let accent = Color(red: 0.545, green: 0.361, blue: 0.965)          // #8b5cf6
    static let accentInk = Color(red: 0.655, green: 0.545, blue: 0.980)       // #a78bfa
    static let onAccent = Color(red: 0.047, green: 0.02, blue: 0.094)
    /// The filled part of a `FillButton`. kit.css says
    /// `color-mix(in srgb, var(--accent) 68%, #000)`, which in gamma-encoded
    /// sRGB is simply each accent component times 0.68.
    static let accentDeep = Color(red: 0.545 * 0.68, green: 0.361 * 0.68, blue: 0.965 * 0.68)

    /// The five muted cover tones (kit.css cov-1..cov-5).
    static let coverTones: [Color] = [
        Color(red: 0.110, green: 0.090, blue: 0.188),
        Color(red: 0.141, green: 0.122, blue: 0.173),
        Color(red: 0.078, green: 0.075, blue: 0.106),
        Color(red: 0.165, green: 0.141, blue: 0.220),
        Color(red: 0.118, green: 0.106, blue: 0.137),
    ]

    /// The one horizontal inset.
    static let inset: CGFloat = 20

    /// The cover column (kit.css `--cov`).
    static let cover: CGFloat = 64

    // spacing scale (kit.css :root)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64

    // type ramp
    static let tXS: CGFloat = 12
    static let tSM: CGFloat = 13
    static let tMD: CGFloat = 15
    static let tLG: CGFloat = 17
    static let tXL: CGFloat = 21
    static let t2XL: CGFloat = 28
}

/// Time formatting identical to the mockup helpers.
enum Fmt {
    /// 1:23:45
    static func hms(_ s: TimeInterval) -> String {
        let t = Int(max(0, s.rounded()))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// 3h 05m / 42m — minutes round, so a 56 s remainder reads "1m".
    static func span(_ s: TimeInterval) -> String {
        let t = Int(max(0, s.rounded()))
        let h = t / 3600
        let m = Int((Double(t % 3600) / 60.0).rounded())
        if h > 0 {
            if m == 60 { return "\(h + 1)h 00m" }
            return "\(h)h \(String(format: "%02d", m))m"
        }
        if m == 0 { return t > 0 ? "<1m" : "0m" }
        return "\(m)m"
    }
}
