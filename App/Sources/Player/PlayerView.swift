import SwiftUI

/// Player — variant A ("Cover top, controls low"), per LOCKED.md:
/// back row, scrimmed square cover OR the chapter wheel (never both),
/// identity, chapter button, scrubber with three times, five transport keys,
/// utilities Speed · Sleep · Chapters.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showChapters = false
    @State private var showSleep = false

    private let speeds: [Double] = [1.0, 1.2, 1.5, 1.75, 2.0]
    private let sleepChoices = [15, 30, 60]

    var body: some View {
        Group {
            if let book = model.currentBook, book.hasAudio {
                content(book)
            } else {
                UnderConstructionView(
                    title: "Audiobook",
                    line: "No audiobook yet — import one from the Files app to start.")
            }
        }
        .background(Theme.bg)
    }

    private func content(_ book: Book) -> some View {
        VStack(spacing: 0) {
            topRow(book)

            ScrollView {
                VStack(spacing: 0) {
                    if showChapters {
                        ChaptersWheelView(
                            book: book,
                            position: model.engine.position,
                            onSelect: { chapter in
                                model.selectChapter(chapter)
                                withAnimation(.easeOut(duration: 0.2)) { showChapters = false }
                            })
                        .frame(height: 216)
                        .padding(.top, 12)
                    } else {
                        cover(book)
                    }

                    identity(book).padding(.top, 20)
                    chapterButton(book).padding(.top, 12)
                    scrubber(book).padding(.top, 16)
                    transport.padding(.top, 14)
                    utilities(book).padding(.top, 18)
                    if showSleep {
                        sleepPicker.padding(.top, 10)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: rows

    private func topRow(_ book: Book) -> some View {
        HStack {
            Button {
                model.tab = .library
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel("Back to library")
            Spacer()
            Text(book.formatWord.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(Theme.ink3)
            Spacer()
            Button {
                model.beginNoteCapture()
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 15))
            }
            .accessibilityLabel("New note")
        }
        .foregroundColor(Theme.ink2)
        .padding(.horizontal, Theme.inset)
        .padding(.top, 6)
        .sheet(isPresented: $model.noteCaptureActive, onDismiss: {
            // cancelled by swipe: still resume if we paused for it
            model.cancelNoteCapture()
        }) {
            NoteSheetView()
                .environmentObject(model)
        }
    }

    /// The square cover on the inset rails, dimmed by a scrim so light
    /// artwork never glares (locked decision).
    private func cover(_ book: Book) -> some View {
        ZStack(alignment: .bottom) {
            CoverView(book: book, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.42)],
                startPoint: .center, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .padding(.top, 12)
        .accessibilityHidden(true)
    }

    private func identity(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.title)
                .font(.system(size: Theme.tXL, weight: .bold))
                .lineLimit(2)
            Text([book.author, book.narrator].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: Theme.tSM))
                .foregroundColor(Theme.ink2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.inset)
    }

    private func chapterButton(_ book: Book) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChapters.toggle()
                showSleep = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                Text(book.currentChapter?.title ?? "Chapter")
                    .lineLimit(1)
            }
            .font(.system(size: Theme.tSM))
            .foregroundColor(Theme.accentInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.inset)
        .accessibilityLabel("Chapters: \(book.currentChapter?.title ?? "none")")
    }

    private func scrubber(_ book: Book) -> some View {
        VStack(spacing: 6) {
            ScrubberView(
                duration: book.duration,
                position: model.engine.position
            ) { target in
                model.engine.seek(to: target)
            }
            HStack {
                Text(Fmt.hms(model.engine.position))
                Spacer()
                Text(chapterLeftText(book))
                Spacer()
                Text("−" + Fmt.hms(book.duration - model.engine.position))
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.ink3)
            .monospacedDigit()
        }
        .padding(.horizontal, Theme.inset)
    }

    private func chapterLeftText(_ book: Book) -> String {
        Fmt.chapterLeft(ChapterMath.timeLeftInChapter(
            position: model.engine.position,
            duration: book.duration,
            count: book.chapterCount))
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button { model.previousChapter() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 22, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Previous chapter")

            Button { model.engine.skipBack(15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 24, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Back 15 seconds")

            Button { model.togglePlay() } label: {
                Image(systemName: model.engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.raise2))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(model.engine.isPlaying ? "Pause" : "Play")

            Button { model.engine.skipForward(30) } label: {
                Image(systemName: "goforward.30").font(.system(size: 24, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Forward 30 seconds")

            Button { model.nextChapter() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 22, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Next chapter")
        }
        .foregroundColor(Theme.ink)
        .padding(.horizontal, Theme.inset)
    }

    private func utilities(_ book: Book) -> some View {
        HStack {
            Button {
                let next = speeds.first(where: { $0 > book.speed }) ?? speeds[0]
                model.setSpeed(next)
            } label: {
                utilItem(value: String(format: "%.1f×", book.speed), name: "Speed")
            }
            .accessibilityLabel("Playback speed \(String(format: "%.1f", book.speed))")
            Button {
                withAnimation { showSleep.toggle(); showChapters = false }
            } label: {
                utilItem(
                    value: model.engine.sleepRemaining.map { "\($0 / 60 >= 1 ? "\(Int(($0 / 60).rounded()))m" : "<1m")" },
                    name: "Sleep",
                    icon: model.engine.sleepRemaining == nil ? "moon" : nil)
            }
            .accessibilityLabel("Sleep timer")
            Button {
                withAnimation { showChapters.toggle(); showSleep = false }
            } label: {
                utilItem(value: nil, name: "Chapters", icon: "list.bullet")
            }
            .accessibilityLabel("Chapters picker")
        }
        .padding(.horizontal, Theme.inset)
    }

    private func utilItem(value: String?, name: String, icon: String? = nil) -> some View {
        VStack(spacing: 4) {
            if let value {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(name)
                .font(.system(size: Theme.tXS))
                .foregroundColor(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var sleepPicker: some View {
        HStack(spacing: 8) {
            ForEach(sleepChoices, id: \.self) { m in
                Button {
                    model.armSleep(minutes: m)
                    withAnimation { showSleep = false }
                } label: {
                    Text("\(m) min")
                        .font(.system(size: Theme.tSM))
                        .foregroundColor(Theme.ink3)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.raise2)
                        )
                }
                .accessibilityLabel("Sleep in \(m) minutes")
            }
            Button {
                model.armSleep(minutes: nil)
                withAnimation { showSleep = false }
            } label: {
                Text("Off")
                    .font(.system(size: Theme.tSM, weight: .semibold))
                    .foregroundColor(Theme.accentInk)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Sleep timer off")
        }
        .padding(.horizontal, Theme.inset)
    }
}

/// Draggable scrubber bound to engine state.
struct ScrubberView: View {
    let duration: TimeInterval
    let position: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @GestureState private var drag: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let frac = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line2).frame(height: 4)
                Capsule().fill(Theme.accentInk).frame(width: max(0, min(width, (drag ?? 0) + frac * width)), height: 4)
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 14, height: 14)
                    .offset(x: max(0, min(width - 14, ((drag ?? 0) + frac * width) - 7)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($drag) { value, state, _ in state = value.location.x }
                    .onEnded { value in
                        guard duration > 0 else { return }
                        let f = min(max(value.location.x / width, 0), 1)
                        onSeek(f * duration)
                    }
            )
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((position / max(duration, 1)) * 100)) percent")
    }
}
