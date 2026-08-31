import SwiftUI

/// The button is its own progress bar — kit.css `.ios .fill`. No spinner, no
/// separate bar. The done part of the pill is `accentDeep`, the rest is the
/// plain accent, and the label reads the state and the percent.
struct FillButton: View {
    enum Phase { case idle, busy, done }

    let label: String
    var fraction: Double = 0
    var phase: Phase = .idle
    var disabled: Bool = false
    /// Read by VoiceOver instead of the visible label, because "Transcribing ·
    /// 42%" does not say what tapping does.
    let accessibilityLabel: String
    let action: () -> Void

    private var isDone: Bool { phase == .done }
    private var isBusy: Bool { phase == .busy }

    /// The mockup disables the button while busy. The app cannot: a running
    /// transcription must stay cancellable. Only `idle` obeys `disabled`.
    private var isInert: Bool { isDone || (disabled && !isBusy) }

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    (isDone ? Theme.raise2 : Theme.accent)
                    if !isDone {
                        Theme.accentDeep
                            .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(isDone ? Theme.ink2 : Theme.onAccent)
                        .frame(width: geo.size.width, alignment: .center)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .opacity(isInert && !isDone ? 0.35 : 1)
        }
        .buttonStyle(FillPress())
        .disabled(isInert)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isBusy ? "\(Int((fraction * 100).rounded())) percent" : "")
    }

    /// kit.css `.ios .fill:not(:disabled):active{opacity:.7}`.
    private struct FillPress: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
