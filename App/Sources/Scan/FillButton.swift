import SwiftUI

/// The button is its own progress bar — the `.ios .fill` block of
/// docs/mockups/kit.css, shown in docs/mockups/transcribe.html. A filled
/// accent pill whose leading `accentDeep` overlay grows with `fraction`,
/// animating linearly; `done` settles into raise2/ink2 with no overlay;
/// `fraction == nil` is a plain pill. No separate bar, no spinner, no ring.
struct FillButton: View {
    let label: String
    let fraction: Double?
    let done: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { // gate-ok: text-labelled action
            Text(label)
                .font(.system(size: Theme.tMD, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    ZStack(alignment: .leading) {
                        Capsule().fill(done ? Theme.raise2 : Theme.accent)
                        if !done, let fraction {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(Theme.accentDeep)
                                    .frame(width: geometry.size.width * clamped(fraction))
                                    .animation(.linear, value: fraction)
                            }
                        }
                    }
                }
                .clipShape(Capsule())
                .foregroundStyle(done ? Theme.ink2 : Theme.onAccent)
                .opacity(disabled && fraction == nil && !done ? 0.35 : 1)
        }
        .buttonStyle(FillPressStyle())
        .disabled(disabled)
    }

    private func clamped(_ fraction: Double) -> Double {
        max(0, min(fraction, 1))
    }
}

/// The pressed pill dims instead of scaling (`.fill:not(:disabled):active` in kit.css).
private struct FillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
