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
                UnderConstructionView(
                    title: "Scan",
                    line: "Scan-to-sync is not built yet — it arrives after notes.")
            }
        }
    }
}
