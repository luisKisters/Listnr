import SwiftUI

@main
struct ListnrApp: App {
    @StateObject private var model: AppModel

    init() {
        let uiTest = ProcessInfo.processInfo.arguments.contains("-uitest")
        let store = ListnrStore(inMemory: uiTest)
        _model = StateObject(wrappedValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

/// The four tabs, always present, exactly as locked.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        withMiniPlayer
            .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// Whether the accessory should exist at all: only with a loaded audiobook,
    /// and never on the Audiobook tab, where the player already is.
    ///
    /// This has to gate the accessory rather than its content. Returning an
    /// empty view from the content still leaves the system drawing the glass
    /// capsule, which reads as an empty bar above the tab bar.
    private var wantsMiniPlayer: Bool {
        model.tab != .audiobook && model.currentBook?.hasAudio == true
    }

    /// `tabViewBottomAccessory(isEnabled:)` only arrived in iOS 26.1 and the
    /// deployment target is 26.0, so 26.0 keeps the same rule by attaching the
    /// accessory only when it is wanted — never an empty rail.
    @ViewBuilder
    private var withMiniPlayer: some View {
        if #available(iOS 26.1, *) {
            tabs.tabViewBottomAccessory(isEnabled: wantsMiniPlayer) {
                MiniPlayerView()
            }
        } else if wantsMiniPlayer {
            tabs.tabViewBottomAccessory { MiniPlayerView() }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $model.tab) {
            Tab("Library", systemImage: "books.vertical", value: AppModel.Tab.library) {
                LibraryView()
            }
            Tab("Audiobook", systemImage: "play.circle", value: AppModel.Tab.audiobook) {
                PlayerView()
            }
            Tab("Reader", systemImage: "book", value: AppModel.Tab.reader) {
                UnderConstructionView(
                    title: "Reader",
                    line: "The reader is not built yet — it arrives with the paired EPUB.")
            }
            Tab("Scan", systemImage: "viewfinder", value: AppModel.Tab.scan) {
                ScanView()
            }
        }
    }
}
