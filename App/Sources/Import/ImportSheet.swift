import SwiftUI
import UniformTypeIdentifiers

/// Import — one row, one picker, plain lines. The same sheet shell as the note
/// sheet: `raise`, corner radius 20, one inset on both rails, no navigation
/// stack, no boxes.
///
/// There is no progress bar. Until the enumeration ends there is no honest
/// fraction to show, so the read phase shows the file name it is on and
/// nothing else (plan amendment 3).
struct ImportSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case idle
        case reading(String)
        case done(added: Int, found: Int, skipped: Int)
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var preview: AppModel.ImportPreview?
    @State private var picking = false
    /// Non-nil while the picker is open for a folder that must be re-picked.
    @State private var repicking: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            folderRow
                .padding(.top, Theme.s4)
            if !model.store.unresolvedFolders.isEmpty {
                needsRepicking
                    .padding(.top, Theme.s5)
            }
            status
                .padding(.top, Theme.s5)
            Spacer(minLength: Theme.s5)
            actions
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.s5)
        .padding(.bottom, Theme.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raise)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handlePick(result)
        }
    }

    // MARK: pieces

    private var head: some View {
        Text("Add books")
            .font(.system(size: Theme.tLG, weight: .semibold))
            .foregroundColor(Theme.ink)
    }

    private var folderRow: some View {
        Button {
            repicking = nil
            picking = true
        } label: {
            HStack(spacing: Theme.s3) {
                Image(systemName: "folder")
                    .font(.system(size: Theme.tMD))
                    .foregroundColor(Theme.ink3)
                Text("Folder — M4B")
                    .font(.system(size: Theme.tMD))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink3)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick a folder of M4B files")
    }

    /// The stop rule made visible: a bookmark that no longer resolves is parked
    /// here with a row that opens the picker again. Never a crash, never an
    /// empty library without a reason.
    private var needsRepicking: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text("NEEDS RE-PICKING")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.1 * 11)
                .foregroundColor(Theme.ink3)
            ForEach(model.store.unresolvedFolders) { folder in
                Button {
                    repicking = folder.id
                    picking = true
                } label: {
                    HStack(spacing: Theme.s3) {
                        Text(folder.displayName.isEmpty ? "Folder" : folder.displayName)
                            .font(.system(size: Theme.tSM))
                            .foregroundColor(Theme.ink2)
                            .lineLimit(1)
                        Spacer(minLength: Theme.s2)
                        Text("Pick again")
                            .font(.system(size: Theme.tSM, weight: .semibold))
                            .foregroundColor(Theme.accentInk)
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick \(folder.displayName) again")
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .idle:
            Text("Every M4B inside the folder is added, sub-folders included.")
                .font(.system(size: Theme.tSM))
                .foregroundColor(Theme.ink3)
        case .reading(let name):
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("Reading")
                    .font(.system(size: Theme.tSM, weight: .semibold))
                    .foregroundColor(Theme.ink2)
                Text(name)
                    .font(.system(size: Theme.tSM))
                    .foregroundColor(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .done(let added, let found, let skipped):
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(resultLine(added: added, found: found))
                    .font(.system(size: Theme.tMD))
                    .foregroundColor(Theme.ink)
                if skipped > 0 {
                    Text("\(skipped) file\(skipped == 1 ? "" : "s") could not be read")
                        .font(.system(size: Theme.tSM))
                        .foregroundColor(Theme.ink3)
                }
            }
        case .failed(let reason):
            Text(reason)
                .font(.system(size: Theme.tSM))
                .foregroundColor(Theme.ink2)
        }
    }

    private func resultLine(added: Int, found: Int) -> String {
        let books = "\(found) audiobook\(found == 1 ? "" : "s") found"
        return "\(books) · \(added) new"
    }

    private var actions: some View {
        HStack {
            Button("Cancel") { // gate-ok: text-labelled action
                dismiss()
            }
            .font(.system(size: Theme.tMD))
            .foregroundColor(Theme.ink3)
            Spacer()
            Button("Add to library") { // gate-ok: text-labelled action
                guard let preview else { return }
                model.commitImport(preview)
                dismiss()
            }
            .font(.system(size: Theme.tMD, weight: canCommit ? .semibold : .regular))
            .foregroundColor(canCommit ? Theme.accentInk : Theme.ink3)
            .disabled(!canCommit)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var canCommit: Bool {
        guard let preview else { return false }
        return !preview.found.isEmpty
    }

    // MARK: picking

    private func handlePick(_ result: Result<[URL], Error>) {
        let repickTarget = repicking
        repicking = nil
        switch result {
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            if let folderID = repickTarget {
                do {
                    try model.rePick(folderID: folderID, url: url)
                    phase = .idle
                } catch {
                    phase = .failed("That folder could not be remembered. Try picking it again.")
                }
                return
            }
            read(url)
        }
    }

    private func read(_ url: URL) {
        preview = nil
        phase = .reading(url.lastPathComponent)
        Task {
            do {
                let scanned = try await model.previewImport(url: url) { name in
                    phase = .reading(name)
                }
                preview = scanned
                phase = .done(
                    added: scanned.newCount, found: scanned.found.count,
                    skipped: scanned.skipped)
            } catch {
                phase = .failed("That folder could not be read. Pick it again.")
            }
        }
    }
}
