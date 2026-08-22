import SwiftUI

/// The under-construction screen for unbuilt tabs. One message, no controls
/// that pretend to work — the locked V0 rule.
struct UnderConstructionView: View {
    let title: String
    let line: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: Theme.t2XL, weight: .bold))
            Text(line)
                .font(.system(size: Theme.tMD))
                .foregroundColor(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .accessibilityElement(children: .combine)
    }
}
