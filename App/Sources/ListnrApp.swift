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
        TabView(selection: $model.tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppModel.Tab.library)
            PlayerView()
                .tabItem { Label("Audiobook", systemImage: "play.circle") }
                .tag(AppModel.Tab.audiobook)
            UnderConstructionView(
                title: "Reader",
                line: "The reader is not built yet — it arrives with the paired EPUB.")
                .tabItem { Label("Reader", systemImage: "book") }
                .tag(AppModel.Tab.reader)
            UnderConstructionView(
                title: "Scan",
                line: "Scan-to-sync is not built yet — it arrives after notes.")
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(AppModel.Tab.scan)
        }
    }
}
