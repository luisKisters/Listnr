import AVFoundation
import SwiftUI
import UIKit

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var camera = CameraController()

    @State private var selectorOpen = false
    @State private var scanBookID: UUID?
    @State private var phase: ScanPhase = .idle
    @State private var match: PageMatch?
    @State private var frozen: UIImage?
    @State private var hasShot = false
    @State private var preparingBookID: UUID?
    /// Set by the tap that asked for the model. The sheet is up while this is
    /// true and the model has not landed.
    @State private var modelSheetOpen = false
    @State private var cameraNotice: String?
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            head
            stage
            bookLine
            key
        }
        .padding(.horizontal, Theme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear { if state == .idle { camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: state) { _, new in
            if new == .idle { camera.start() } else if new != .reading { camera.stop() }
        }
        .onChange(of: model.preparationProgress) { _, new in
            if new == nil { preparingBookID = nil }
        }
        // The model landing closes the sheet itself; the queued book is
        // already preparing by then.
        .onChange(of: model.modelDownload) { _, new in
            if new == .ready { modelSheetOpen = false }
        }
        .sheet(isPresented: Binding(
            get: { modelSheetOpen && model.modelDownload != .ready },
            set: { if !$0 { modelSheetOpen = false } })) {
            ModelDownloadSheet(
                state: model.modelDownload,
                start: { model.downloadModel(then: book?.id) },
                stop: model.stopModelDownload,
                dismiss: { modelSheetOpen = false })
            .presentationDetents([.height(300)])
            .presentationBackground(Theme.bg)
            // A tap outside must not throw a 460 MB download away.
            .interactiveDismissDisabled(isDownloadingModel)
        }
    }

    // MARK: state

    private var books: [Book] {
        model.store.books.filter { $0.hasAudio && !$0.isMissing }
    }

    private var book: Book? {
        if let id = scanBookID, let found = books.first(where: { $0.id == id }) { return found }
        return model.currentBook?.hasAudio == true ? model.currentBook : books.first
    }

    private var state: ScanState {
        ScanLogic.state(
            hasBook: book != nil,
            selectorOpen: selectorOpen,
            hasTranscript: book?.hasTranscript ?? false,
            preparation: preparingBookID == book?.id ? model.preparationProgress : nil,
            phase: phase)
    }

    private var keyKind: ScanKey {
        ScanLogic.key(
            for: state,
            selectionHasTranscript: book?.hasTranscript ?? false,
            cameraReady: cameraReady,
            model: model.modelDownload)
    }

    private var isDownloadingModel: Bool {
        if case .downloading = model.modelDownload { return true }
        return false
    }

    private var cameraReady: Bool {
        #if DEBUG
        return camera.isReady || ScanFixture.isActive
        #else
        return camera.isReady
        #endif
    }

    // MARK: the close slot

    private var head: some View {
        HStack {
            Spacer()
            if ScanLogic.closes(state) {
                Button(action: tapClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(closeAccessibilityLabel)
            }
        }
        .frame(height: 44)
    }

    private var closeAccessibilityLabel: String {
        switch state {
        case .preparing: return "Stop preparing"
        case .reading, .searching: return "Cancel"
        default: return "Back to the viewfinder"
        }
    }

    private func tapClose() {
        if selectorOpen {
            selectorOpen = false
            return
        }
        switch state {
        case .preparing:
            model.cancelPreparation()
        case .reading, .searching:
            readTask?.cancel()
            readTask = nil
            backToViewfinder()
        default:
            backToViewfinder()
        }
    }

    // MARK: the frame

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(state == .idle ? Theme.raise : Theme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line2, lineWidth: 1))
            if state == .idle, camera.isReady {
                CameraPreviewView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let frozen {
                Image(uiImage: frozen)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.18)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ScanBrackets()
                .stroke(Theme.line, lineWidth: 1)
                .opacity(state == .idle ? 1 : 0.4)
            if state == .selecting {
                bookDrum
            } else {
                frameText
                    .padding(.horizontal, Theme.s5)
                    .padding(.vertical, 46)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.s5)
    }

    @ViewBuilder
    private var frameText: some View {
        VStack(spacing: 0) {
            switch state {
            case .noBook:
                line("No audiobook is loaded, so there is nothing to match a page against.")
            case .preparing(let fraction):
                line("Listening through the audio once, so a page has something to match against.")
                sub("\(Fmt.span((book?.duration ?? 0) * fraction)) of \(Fmt.span(book?.duration ?? 0))")
                sub("This keeps running while you listen.")
            case .notPrepared:
                line("A page can only be matched against a transcript, and this book has none yet.")
                sub(model.preparationNotice ?? "Preparing runs in the background and takes a while.")
            case .reading:
                line("Reading the page.")
            case .searching:
                line("Looking for those words in the audio.")
                sub("Searching the transcript of \(book?.title ?? "")." )
            case .matched:
                if let match {
                    Text(match.snippet)
                        .font(.system(size: Theme.tMD))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                    Text(Fmt.hms(match.time))
                        .font(.system(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .padding(.top, Theme.s4)
                    if let chapter = chapterTitle(at: match.time) {
                        Text(chapter)
                            .font(.system(size: Theme.tSM))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                            .padding(.top, Theme.s1)
                    }
                }
            case .noMatch:
                line("No match in this book.")
                sub("Catch a few more lines, or try the facing page.")
            case .idle:
                if let cameraNotice {
                    sub(cameraNotice)
                } else if !cameraReady {
                    sub("The camera is not available — allow it in Settings.")
                } else if !hasShot {
                    sub("Fill the frame with the page")
                }
            case .selecting:
                EmptyView()
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.tMD))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
    }

    private func sub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.tSM))
            .foregroundStyle(Theme.ink3)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.s2)
    }

    private var bookDrum: some View {
        Picker("Book to match against", selection: Binding(
            get: { scanBookID ?? book?.id },
            set: { newValue in
                scanBookID = newValue
                UISelectionFeedbackGenerator().selectionChanged()
            })) {
            ForEach(books) { candidate in
                HStack {
                    Text(candidate.title)
                        .font(.system(size: Theme.tLG, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(candidate.hasTranscript ? "ready" : "not prepared")
                        .font(.system(size: Theme.tXS))
                        .foregroundStyle(Theme.ink3)
                }
                .tag(Optional(candidate.id))
            }
        }
        .pickerStyle(.wheel)
        .padding(.horizontal, Theme.s4)
    }

    // MARK: the book line, under the frame

    private var bookLine: some View {
        HStack(spacing: Theme.s1) {
            Spacer()
            Text("Point at a page of")
                .font(.system(size: Theme.tSM))
                .foregroundStyle(Theme.ink3)
            Button {
                selectorOpen.toggle()
            } label: {
                HStack(spacing: Theme.s1) {
                    Text(book?.title ?? "no book")
                        .font(.system(size: Theme.tSM))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(selectorOpen ? 180 : 0))
                }
                .foregroundStyle(selectorOpen ? Theme.accentInk : Theme.ink)
            }
            .disabled(books.isEmpty)
            .accessibilityLabel("Book to match against: \(book?.title ?? "no book")")
            Spacer()
        }
        .frame(height: 44)
    }

    // MARK: the button

    private var key: some View {
        Button(action: tapKey) {
            keyLabel
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(Theme.onAccent)
                .opacity(keyDisabled && !isWorking ? 0.3 : 1)
        }
        .disabled(keyDisabled)
        .accessibilityLabel(keyAccessibilityLabel)
        .padding(.vertical, Theme.s5)
    }

    @ViewBuilder
    private var keyLabel: some View {
        switch keyKind {
        case .shutter:
            Image(systemName: "text.viewfinder")
                .font(.system(size: 24, weight: .regular))
        case .working(let fraction):
            HStack(spacing: Theme.s2) {
                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.01, min(fraction, 1)))
                        .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 24, height: 24)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: Theme.tSM, weight: .semibold))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.onAccent)
                }
            }
        case .word(let word):
            Text(word)
                .font(.system(size: Theme.tMD, weight: .semibold))
        }
    }

    private var isWorking: Bool {
        if case .working = keyKind { return true }
        return false
    }

    private var keyDisabled: Bool {
        switch keyKind {
        case .shutter(let enabled): return !enabled
        case .working: return true
        case .word: return false
        }
    }

    private var keyAccessibilityLabel: String {
        switch keyKind {
        case .shutter:
            if state == .selecting { return "Choose the book to match against" }
            if state == .noBook { return "No audiobook is loaded" }
            return cameraReady
                ? "Read the page in front of the camera"
                : "The camera is not available"
        case .working(let fraction):
            if let fraction {
                let percent = Int((fraction * 100).rounded())
                return isDownloadingModel
                    ? "Downloading the model, \(percent) per cent done"
                    : "Preparing this book, \(percent) per cent done"
            }
            return state == .reading ? "Reading the page" : "Searching the transcript"
        case .word(let word):
            if state == .matched, let match { return "Jump to \(Fmt.hms(match.time))" }
            return word
        }
    }

    private func tapKey() {
        if case .word("Download the model") = keyKind, let book {
            preparingBookID = book.id
            modelSheetOpen = true
            return
        }
        switch state {
        case .selecting:
            selectorOpen = false
            if let book { requestPreparation(book) }
        case .notPrepared:
            if let book { requestPreparation(book) }
        case .matched:
            guard let book, let match else { return }
            model.jumpFromScan(bookID: book.id, time: match.time)
            backToViewfinder()
        case .noMatch:
            backToViewfinder()
        case .idle:
            shoot()
        default:
            break
        }
    }

    // MARK: the loop

    private func backToViewfinder() {
        phase = .idle
        match = nil
    }

    private func shoot() {
        guard let book, let transcript = Transcript.load(bookID: book.id) else { return }
        hasShot = true
        cameraNotice = nil
        phase = .reading
        #if DEBUG
        if ScanFixture.isActive {
            examine(ScanFixture.pageImage(), transcript: transcript)
            return
        }
        #endif
        camera.captureStill { image in
            examine(image, transcript: transcript)
        }
    }

    private func examine(_ image: UIImage?, transcript: Transcript) {
        guard phase == .reading else { return }
        guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
            cameraNotice = "The camera could not take that photo — try again."
            phase = .idle
            return
        }
        frozen = image
        camera.stop()
        readTask = Task { await read(data: data, transcript: transcript) }
    }

    private func read(data: Data, transcript: Transcript) async {
        let text = await Task.detached { () -> String? in
            guard let image = UIImage(data: data) else { return nil }
            return try? PageOCR.recognize(image: image).text
        }.value
        guard !Task.isCancelled else { return }
        guard let text, !text.isEmpty else {
            phase = .noMatch
            return
        }
        phase = .searching
        let found = await Task.detached {
            PageMatcher.match(ocr: text, transcript: transcript.words)
        }.value
        guard !Task.isCancelled else { return }
        match = found
        phase = found == nil ? .noMatch : .matched
    }

    private func chapterTitle(at time: TimeInterval) -> String? {
        guard let book, let i = ChapterMath.index(at: time, in: book.chapters) else { return nil }
        return book.chapters[i].title
    }

    // MARK: the model, downloaded once

    /// Without the model there is nothing to prepare with, so the tap asks for
    /// the model instead and the book is queued behind it.
    private func requestPreparation(_ book: Book) {
        preparingBookID = book.id
        guard model.modelDownload == .ready else {
            modelSheetOpen = true
            return
        }
        model.prepareForScanning(bookID: book.id)
    }
}

struct ScanBrackets: Shape {
    var inset: CGFloat = 16
    var arm: CGFloat = 26
    var radius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        for corner in 0..<4 {
            let right = corner == 1 || corner == 3
            let bottom = corner >= 2
            let x = right ? box.maxX : box.minX
            let y = bottom ? box.maxY : box.minY
            let dx: CGFloat = right ? -1 : 1
            let dy: CGFloat = bottom ? -1 : 1
            path.move(to: CGPoint(x: x, y: y + dy * arm))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(
                to: CGPoint(x: x + dx * radius, y: y),
                control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        return path
    }
}

/// The 460 MB speech model, asked for once. There is no pause: FluidAudio
/// cannot resume a download, so a pause would lie — the second control is a
/// stop that says the next one starts over.
struct ModelDownloadSheet: View {
    let state: ModelDownload
    let start: () -> Void
    let stop: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("The audio AI model")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(message)
                .font(.system(size: Theme.tMD))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.s2)
            if case .downloading(let fraction) = state {
                progress(fraction)
            }
            Spacer(minLength: Theme.s5)
            Button(action: isDownloading ? stop : start) {
                Text(word)
                    .font(.system(size: Theme.tMD, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
            .accessibilityLabel(keyAccessibilityLabel)
            // No dead controls: refusing is only offered while there is
            // something to refuse.
            if !isDownloading {
                Button(action: dismiss) {
                    Text("Not now")
                        .font(.system(size: Theme.tSM))
                        .foregroundStyle(Theme.ink3)
                        .frame(height: 44)
                }
                .accessibilityLabel("Not now")
            }
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.s6)
        .padding(.bottom, Theme.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    /// The honest fraction, on a hairline. Nothing here moves on its own.
    private func progress(_ fraction: Double) -> some View {
        HStack(spacing: Theme.s4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line2)
                    Rectangle()
                        .fill(Theme.accentInk)
                        .frame(width: geometry.size.width * max(0, min(fraction, 1)))
                }
            }
            .frame(height: 1)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: Theme.tSM, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.top, Theme.s5)
        .accessibilityElement()
        .accessibilityLabel("Downloading, \(Int((fraction * 100).rounded())) per cent done")
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private var word: String {
        switch state {
        case .downloading: return "Stop"
        case .failed: return "Try again"
        default: return "Download"
        }
    }

    private var keyAccessibilityLabel: String {
        switch state {
        case .downloading: return "Stop the download — the next one starts over"
        case .failed: return "Try downloading the model again"
        default: return "Download the audio AI model"
        }
    }

    private var message: String {
        switch state {
        case .failed:
            return "The model could not be downloaded. Check the connection and try again."
        case .downloading:
            return "Downloading once. It stays on this device afterwards."
        default:
            return "Matching a page needs the speech model on this device. It downloads once "
                + "and stays. Keep Listnr open — it stops when the phone locks."
        }
    }
}

#Preview("Model download") {
    ModelDownloadSheet(state: .missing, start: {}, stop: {}, dismiss: {})
}

#Preview("Model downloading") {
    ModelDownloadSheet(state: .downloading(0.42), start: {}, stop: {}, dismiss: {})
}

#Preview("Model download failed") {
    ModelDownloadSheet(state: .failed, start: {}, stop: {}, dismiss: {})
}
