import SwiftUI

/// The design tokens of docs/mockups/kit.css, translated once. Views never invent
/// colors or sizes; the three rules live in docs/DESIGN.md.
///
/// Scheme 1 (Black · Green) only; the purple scheme never ships.
/// Green was decided by the owner on 2026-08-24. `accent` is the filled mark
/// (play key, shutter, the band inside a cover); `accentInk` is the same green
/// at text weight, held one notch back because neon buzzes at type size.
enum Theme {
    static let bg = Color(red: 0.02, green: 0.02, blue: 0.02)                 // #050505
    static let raise = Color(red: 0.051, green: 0.051, blue: 0.051)           // #0d0d0d
    static let raise2 = Color(red: 0.086, green: 0.078, blue: 0.094)          // #161418
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.72)
    static let ink3 = Color.white.opacity(0.50)
    static let line = Color.white.opacity(0.15)
    static let line2 = Color.white.opacity(0.09)
    static let accent = Color(red: 0.169, green: 1.0, blue: 0.243)            // #2bff3e
    static let accentInk = Color(red: 0.361, green: 0.894, blue: 0.420)       // #5ce46b
    static let onAccent = Color(red: 0.012, green: 0.075, blue: 0.024)        // #031306

    /// accent blended 68% with black — kit.css `color-mix(in srgb, var(--accent)
    /// 68%, #000)`; the fill button's progress overlay (docs/mockups/transcribe.html).
    static let accentDeep = Color(red: 0.169 * 0.68, green: 1.0 * 0.68, blue: 0.243 * 0.68)

    /// The five muted cover tones (kit.css cov-1..cov-5).
    static let coverTones: [Color] = [
        Color(red: 0.082, green: 0.102, blue: 0.082),   // #151a15
        Color(red: 0.114, green: 0.122, blue: 0.110),   // #1d1f1c
        Color(red: 0.071, green: 0.078, blue: 0.071),   // #121412
        Color(red: 0.137, green: 0.145, blue: 0.133),   // #232522
        Color(red: 0.102, green: 0.110, blue: 0.098),   // #1a1c19
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
