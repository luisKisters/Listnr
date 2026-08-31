import SwiftUI

/// `docs/mockups/transcribe.html`, 1:1. Two long jobs, one control each, and
/// nothing else — the button is its own progress bar.
///
/// It lives in the Scan tab because transcription is what scan-to-position
/// needs first and the tab otherwise leads nowhere. When the real Scan tab
/// lands, this screen moves behind its "Prepare this book" state.
struct TranscriptionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // The job is its own `ObservableObject`, and a nested one does not
        // refresh a view that only observes `AppModel` — hence the split.
        TranscriptionScreen(job: model.transcription, book: model.currentBook)
    }
}

private struct TranscriptionScreen: View {
    @ObservedObject var job: TranscriptionJob
    let book: Book?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transcription")
                .font(.system(size: Theme.t2XL, weight: .bold))
                .tracking(Theme.t2XL * -0.025)
                .foregroundColor(Theme.ink)
                .padding(.top, Theme.s5)

            Text("Listnr reads the audio on this phone. Nothing leaves the device.")
                .font(.system(size: 14))
                .foregroundColor(Theme.ink2)
                .lineSpacing(14 * 0.45)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.s2)

            modelJob
            bookJob

            // Not in the mockup, and deliberately so: a refused start or a
            // failed download must say why. One quiet line, never a silent
            // failure.
            if let notice = job.notice {
                Text(notice)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.s5)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    // MARK: job 1 — the speech model

    private var modelJob: some View {
        job(label: "Speech model", key: "Parakeet · 1.2 GB · once per phone") {
            switch job.model {
            case .missing:
                FillButton(
                    label: "Download model", accessibilityLabel: "Download the speech model",
                    action: { job.downloadModel() })
            case .downloading(let fraction):
                FillButton(
                    label: "Downloading · \(percent(fraction))%", fraction: fraction, phase: .busy,
                    accessibilityLabel: "Stop downloading the speech model",
                    action: { job.stopModelDownload() })
            case .ready:
                FillButton(
                    label: "Model ready", phase: .done, accessibilityLabel: "The speech model is ready",
                    action: {})
            }
        }
    }

    // MARK: job 2 — the book

    private var bookJob: some View {
        job(label: bookLabel, key: bookKey) { bookButton }
    }

    private var bookLabel: String { book?.title ?? "No audiobook loaded" }

    private var bookKey: String {
        guard let book else { return "Open a book in Library first." }
        let estimate = TranscriptionEstimate.text(
            duration: book.duration, speed: TranscriptionEstimate.speed())
        return "\(TranscriptionEstimate.duration(book.duration)) · \(estimate) on this phone"
    }

    @ViewBuilder
    private var bookButton: some View {
        if let book, !book.isMissing {
            if case .running(let id, let fraction) = job.state, id == book.id {
                FillButton(
                    label: "Transcribing · \(percent(fraction))%", fraction: fraction, phase: .busy,
                    accessibilityLabel: "Stop transcribing \(book.title)",
                    action: { job.stop(bookID: book.id) })
            } else if book.hasTranscript {
                FillButton(
                    label: "Transcribed", phase: .done,
                    accessibilityLabel: "\(book.title) is transcribed", action: {})
            } else {
                FillButton(
                    label: "Transcribe book", disabled: job.model != .ready,
                    accessibilityLabel: "Transcribe \(book.title)",
                    action: { job.start(bookID: book.id) })
            }
        } else {
            FillButton(
                label: "Transcribe book", disabled: true,
                accessibilityLabel: "Transcribe book", action: {})
        }
    }

    // MARK: the shared job block — kit.css `.tx-job`

    private func job(
        label: String, key: String, @ViewBuilder button: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 16))
                .tracking(16 * -0.01)
                .foregroundColor(Theme.ink)
                .lineLimit(1)
            Text(key)
                .font(.system(size: Theme.tXS))
                .foregroundColor(Theme.ink3)
                .padding(.top, 2)
            button().padding(.top, Theme.s3)
        }
        .padding(.top, Theme.s6)
    }

    private func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}
