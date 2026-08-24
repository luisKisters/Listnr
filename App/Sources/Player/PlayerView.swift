import SwiftUI

/// Player — decluttered variant A. A fixed column, never a scroll view:
/// top row · scrimmed cover OR the chapter wheel (never both) · identity with
/// the chapter line · a flexible gap · scrubber with two times · five transport
/// keys · the utility row (speed left, note pencil right) · the inline sleep
/// picker. Nothing here scrolls and nothing touches the tab bar.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showChapters = false
    @State private var showSleep = false
    /// The measured height of everything in the column that is not the cover
    /// and not the flexible gap. Measured rather than asserted: a constant that
    /// is one point too big steals a point from the cover, and the cover has to
    /// land exactly on the rails (kit.css rule 1, one inset).
    @State private var fixedHeight: CGFloat = 0

    private let speeds: [Double] = [1.0, 1.2, 1.5, 1.75, 2.0]
    private let sleepChoices = [15, 30, 60]

    private let topRowHeight: CGFloat = 32
    private let transportHeight: CGFloat = 64   // the play key's circle
    private let utilityHeight: CGFloat = 44
    private let wheelHeight: CGFloat = 216

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
        GeometryReader { geo in
            VStack(spacing: 0) {
                topRow(book).measuredAsFixed()

                if showChapters, !book.chapters.isEmpty {
                    ChaptersWheelView(
                        book: book,
                        position: model.engine.position,
                        onSelect: { chapter in
                            model.selectChapter(chapter)
                            withAnimation(.easeOut(duration: 0.2)) { showChapters = false }
                        })
                        .frame(height: wheelHeight)
                        .padding(.top, Theme.s5)
                } else {
                    cover(book, side: coverSide(in: geo.size))
                        .padding(.top, Theme.s5)
                }

                identity(book)
                    .padding(.top, Theme.s6)
                    .measuredAsFixed()

                Spacer(minLength: Theme.s6)

                VStack(spacing: 0) {
                    scrubber(book)
                    transport
                    utilities(book).padding(.top, Theme.s6)
                    if showSleep { sleepPicker }
                }
                .measuredAsFixed()
            }
            .padding(.bottom, Theme.s5)
            .onPreferenceChange(FixedHeightKey.self) { fixedHeight = $0 }
        }
    }

    /// The cover is a square on the rails. It only gives ground when a
    /// rail-to-rail square plus the fixed rows plus the gap at its `Theme.s6`
    /// minimum would not fit — and then only by what is actually missing.
    /// Everything but the cover's own margins is measured, so nothing is
    /// reserved twice.
    private func coverSide(in size: CGSize) -> CGFloat {
        let width = size.width - Theme.inset * 2
        guard fixedHeight > 0 else { return width }
        let margins = Theme.s5      // cover top margin
            + Theme.s6              // the flexible gap, at its minimum
            + Theme.s5              // clearance to the tab bar
        return max(88, min(width, size.height - fixedHeight - margins))
    }

    // MARK: rows

    /// `1fr auto 1fr`: two equal side rails keep the word centred.
    private func topRow(_ book: Book) -> some View {
        HStack(spacing: Theme.s2) {
            HStack(spacing: 0) {
                Button {
                    model.tab = .library
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 36, height: topRowHeight)
                }
                .accessibilityLabel("Back to library")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("AUDIOBOOK")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.1 * 11)
                .foregroundColor(Theme.ink3)
                .lineLimit(1)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    withAnimation { showSleep.toggle(); showChapters = false }
                } label: {
                    HStack(spacing: Theme.s1 + 2) {
                        if let left = sleepLeftText {
                            Text(left)
                                .font(.system(size: Theme.tXS))
                                .foregroundColor(Theme.ink3)
                                .monospacedDigit()
                        }
                        Image(systemName: "moon")
                            .font(.system(size: 19, weight: .medium))
                    }
                    .frame(height: topRowHeight)
                    .contentShape(Rectangle())
                }
                .foregroundColor(showSleep ? Theme.accentInk : Theme.ink2)
                .accessibilityLabel("Sleep timer")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: topRowHeight)
        .foregroundColor(Theme.ink2)
        .padding(.horizontal, Theme.inset)
        .sheet(isPresented: $model.noteCaptureActive, onDismiss: {
            // cancelled by swipe: still resume if we paused for it
            model.cancelNoteCapture()
        }) {
            NoteSheetView()
                .environmentObject(model)
        }
    }

    /// "28m", and "<1m" once the timer drops under a minute. Nil when unarmed.
    private var sleepLeftText: String? {
        guard let left = model.engine.sleepRemaining, left > 0 else { return nil }
        if left < 60 { return "<1m" }
        return "\(Int((left / 60).rounded(.up)))m"
    }

    /// The square cover on the inset rails, dimmed by a scrim so light
    /// artwork never glares (locked decision).
    private func cover(_ book: Book, side: CGFloat) -> some View {
        CoverView(book: book, cornerRadius: 12)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Theme.bg.opacity(0.20), location: 0),
                        .init(color: Theme.bg.opacity(0.02), location: 0.34),
                        .init(color: Theme.bg.opacity(0.42), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.inset)
            .accessibilityHidden(true)
    }

    private func identity(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(book.title)
                .font(.system(size: Theme.tXL, weight: .bold))
                .tracking(-0.03 * Theme.tXL)
                .lineLimit(2)
            Text([book.author, book.narrator].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: Theme.tSM))
                .foregroundColor(Theme.ink2)
                .lineLimit(1)
                .padding(.top, 3)
            if !book.chapters.isEmpty {
                chapterLine(book)
            }
            // A file that is not local yet, or a folder whose scope was
            // refused, says so here instead of failing silently (plan risk 4).
            if let notice = model.playbackNotice {
                Text(notice)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.inset)
    }

    /// The only control that opens the wheel; it tints while the wheel is up.
    /// Rendered only for a book that has real chapters, so it is never a dead
    /// control — no chapters means no line at all.
    private func chapterLine(_ book: Book) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChapters.toggle()
                showSleep = false
            }
        } label: {
            Text(book.currentChapter?.title ?? "")
                .font(.system(size: Theme.tSM, weight: .medium))
                .tracking(-0.01 * Theme.tSM)
                .lineLimit(1)
                .foregroundColor(showChapters ? Theme.accentInk : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .padding(.top, Theme.s2)
        .accessibilityLabel("Chapters: \(book.currentChapter?.title ?? "none")")
    }

    private func scrubber(_ book: Book) -> some View {
        VStack(spacing: 2) {
            ScrubberView(
                duration: book.duration,
                position: model.engine.position
            ) { target in
                model.engine.seek(to: target)
            }
            HStack(spacing: Theme.s2) {
                Text(Fmt.hms(model.engine.position))
                Spacer(minLength: 0)
                Text("−" + Fmt.hms(book.duration - model.engine.position))
            }
            .font(.system(size: 11.5))
            .foregroundColor(Theme.ink3)
            .monospacedDigit()
        }
        .padding(.horizontal, Theme.inset)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button { model.previousChapter() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 21, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous chapter")

            Button { model.engine.skipBack(15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 25, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back 15 seconds")

            Button { model.togglePlay() } label: {
                Image(systemName: model.engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.onAccent)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.accent))
            }
            .accessibilityLabel(model.engine.isPlaying ? "Pause" : "Play")

            Button { model.engine.skipForward(30) } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 25, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Forward 30 seconds")

            Button { model.nextChapter() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 21, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next chapter")
        }
        .frame(height: transportHeight)
        .foregroundColor(Theme.ink2)
        .padding(.horizontal, Theme.inset)
    }

    /// Two items only: the speed value on the left rail, the note pencil with
    /// its count on the right. No word labels, no Chapters, no moon.
    private func utilities(_ book: Book) -> some View {
        HStack(spacing: Theme.s2) {
            Button {
                let next = speeds.first(where: { $0 > book.speed }) ?? speeds[0]
                model.setSpeed(next)
            } label: {
                Text(String(format: "%.1f×", book.speed))
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.02 * 14)
                    .foregroundColor(Theme.ink)
                    .monospacedDigit()
                    .frame(minHeight: utilityHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playback speed \(String(format: "%.1f", book.speed))")

            Spacer(minLength: 0)

            Button {
                model.beginNoteCapture()
            } label: {
                HStack(spacing: Theme.s1 + 2) {
                    if noteCount > 0 {
                        Text("\(noteCount)")
                            .font(.system(size: Theme.tXS))
                            .foregroundColor(Theme.ink3)
                            .monospacedDigit()
                    }
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(Theme.ink2)
                }
                .frame(minHeight: utilityHeight, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("New note")
        }
        .frame(height: utilityHeight)
        .padding(.horizontal, Theme.inset)
    }

    private var noteCount: Int { model.notesForCurrentBook.count }

    /// kit.css `.inline` — it pushes the layout, it never floats over it.
    private var sleepPicker: some View {
        VStack(spacing: 0) {
            Theme.line2.frame(height: 1)
            HStack(spacing: 6) {
                ForEach(sleepChoices, id: \.self) { m in
                    Button {
                        model.armSleep(minutes: m)
                        withAnimation { showSleep = false }
                    } label: {
                        sleepOption("\(m) min", active: armedMinutes == m)
                    }
                    .accessibilityLabel("Sleep in \(m) minutes")
                }
                Button {
                    model.armSleep(minutes: nil)
                    withAnimation { showSleep = false }
                } label: {
                    sleepOption("Off", active: !isSleepArmed)
                }
                .accessibilityLabel("Sleep timer off")
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, Theme.inset)
    }

    /// The armed choice comes from the engine — the picker keeps no copy of
    /// it, so the highlight cannot drift from the timer that is running.
    private var armedMinutes: Int? { model.engine.sleepArmedMinutes }
    private var isSleepArmed: Bool { armedMinutes != nil }

    private func sleepOption(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: active ? .semibold : .regular))
            .foregroundColor(active ? Theme.ink : Theme.ink3)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// The summed height of the column's fixed rows, so the cover can claim
/// exactly the rest. Every contributor adds itself; the gap and the cover's
/// own margins are the only constants left in the sum.
private struct FixedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private extension View {
    func measuredAsFixed() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: FixedHeightKey.self, value: proxy.size.height)
            }
        }
    }
}

/// Draggable scrubber bound to engine state. 2pt track, 10pt knob (kit.css
/// `.tl-track` / `.tl-knob`).
struct ScrubberView: View {
    let duration: TimeInterval
    let position: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @GestureState private var drag: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let frac = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let width = geo.size.width
            let x = max(0, min(width, (drag ?? 0) + frac * width))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line2).frame(height: 2)
                Capsule().fill(Theme.accentInk).frame(width: x, height: 2)
                Circle()
                    .fill(Theme.accentInk)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, min(width - 10, x - 5)))
            }
            .frame(maxHeight: .infinity)
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
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((position / max(duration, 1)) * 100)) percent")
    }
}
