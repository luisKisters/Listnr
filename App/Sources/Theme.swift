import SwiftUI

/// The design tokens of mockups/kit.css, translated once. Views never invent
/// colors or sizes; the three rules live in design/LOCKED.md.
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

/// A placeholder cover: muted tone gradient with the title initial. Sample
/// libraries ship without real artwork by policy (PRODUCT.md evidence rules).
struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 10
    /// Variant B: when set, a progress band rides inside the cover's bottom
    /// edge. `nil` for an unstarted book and for screens that do not want it.
    var progress: Double?

    var body: some View {
        ZStack(alignment: .center) {
            LinearGradient(
                colors: [tone, tone.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(String(book.title.prefix(1)))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(Theme.ink2)
        }
        .overlay(alignment: .bottom) {
            if let progress {
                CoverProgressBand(fraction: progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.line2, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var tone: Color {
        Theme.coverTones[(book.tone - 1 + Theme.coverTones.count) % Theme.coverTones.count]
    }
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

    /// "58s left" / "4m 12s left"
    static func chapterLeft(_ s: TimeInterval) -> String {
        let t = Int(max(0, s.rounded()))
        if t >= 60 { return "\((t % 3600) / 60)m \(String(format: "%02d", t % 60))s left" }
        return "\(t)s left"
    }
}

/// kit.css `.cover .inline-p` — the band that rides inside the cover's own
/// bottom edge: a hairline, a dark plate, and the accent filled from the left.
/// It is always clipped by the cover's corner radius, so it cannot escape.
struct CoverProgressBand: View {
    let fraction: Double

    var body: some View {
        VStack(spacing: 0) {
            Theme.ink3.frame(height: 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.62)
                    Theme.accent
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
