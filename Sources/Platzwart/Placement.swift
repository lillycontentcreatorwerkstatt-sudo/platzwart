import AppKit
import SwiftUI

/// Eine Datei, für die du wissen willst, wohin sie gehört.
struct PendingFile: Identifiable {
    var id: String { url.path }
    let url: URL
}

/// Eine Datei aus Downloads oder vom Schreibtisch.
struct LooseFile: Identifiable {
    var id: String { url.path }
    let url: URL
    let source: String
    let size: Int64
    let modified: Date?
}

/// „Datei einsortieren“ und „Liegt noch rum“: Du wählst eine Datei, Platzwart schlägt Ordner vor,
/// du entscheidest. Verschoben wird nur über den Knopf „Hierhin verschieben“.
final class PlacementController: ObservableObject {
    @Published var pendingFile: PendingFile?
    @Published var showLooseList = false
    @Published var looseFiles: [LooseFile] = []
    /// Ordner, auf die macOS den Zugriff verweigert hat (z. B. „Downloads“)
    @Published var blockedFolders: [String] = []
    @Published var isLoadingLoose = false
    @Published var lastMoved: (name: String, folder: URL)?

    // MARK: - Datei auswählen

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.message = "Welche Datei möchtest du einsortieren?"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingFile = PendingFile(url: url)
    }

    // MARK: - Vorschläge

    func suggestions(for file: URL, index: PlacementIndex?) -> [PlacementIndex.Suggestion] {
        guard let index else { return [] }
        let parent = file.deletingLastPathComponent().resolvingSymlinksInPath().path
        return index.suggest(query: file.deletingPathExtension().lastPathComponent,
                             fileExtension: file.pathExtension, limit: 10)
            .filter { suggestion in
                // Hauptordner wie „Dokumente“ sind zu ungenau, und der eigene Ordner ergibt keinen Sinn.
                suggestion.folder.display.contains(" › ") && suggestion.folder.path != parent
            }
            .prefix(4)
            .map { $0 }
    }

    // MARK: - Liegt noch rum

    func loadLooseFiles() {
        isLoadingLoose = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (found, blocked) = Self.collectLooseFiles()
            DispatchQueue.main.async {
                self?.looseFiles = found
                self?.blockedFolders = blocked
                self?.isLoadingLoose = false
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func collectLooseFiles() -> ([LooseFile], [String]) {
        let fm = FileManager.default
        let sources: [(String, FileManager.SearchPathDirectory)] = [
            ("Downloads", .downloadsDirectory), ("Schreibtisch", .desktopDirectory)
        ]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var list: [LooseFile] = []
        var blocked: [String] = []
        for (name, directory) in sources {
            guard let folder = fm.urls(for: directory, in: .userDomainMask).first else { continue }
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                         options: [.skipsHiddenFiles]) else {
                blocked.append(name)
                continue
            }
            for item in items {
                guard let v = try? item.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
                list.append(LooseFile(url: item, source: name, size: Int64(v.fileSize ?? 0),
                                      modified: v.contentModificationDate))
            }
        }
        return (list.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }, blocked)
    }

    // MARK: - Verschieben

    /// Gibt `true` zurück, wenn verschoben wurde.
    @discardableResult
    func move(_ file: URL, to folder: URL) -> Bool {
        let destination = folder.appendingPathComponent(file.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            showError("Dort liegt schon eine Datei mit dem Namen „\(file.lastPathComponent)“. Es wurde nichts verschoben.")
            return false
        }
        do {
            try FileManager.default.moveItem(at: file, to: destination)
            lastMoved = (file.lastPathComponent, folder)
            looseFiles.removeAll { $0.url == file }
            return true
        } catch {
            showError("Verschieben hat nicht geklappt: \(error.localizedDescription)")
            return false
        }
    }

    /// Ordner selbst wählen und dorthin verschieben. Gibt `true` zurück, wenn verschoben wurde.
    func moveToChosenFolder(_ file: URL, startingAt start: URL?) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Hierhin verschieben"
        panel.message = "Wohin soll „\(file.lastPathComponent)“?"
        panel.directoryURL = start ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        return move(file, to: target)
    }

    // MARK: - Papierkorb

    /// Legt die Datei nach Rückfrage in den macOS-Papierkorb (nicht endgültig gelöscht).
    /// Gibt `true` zurück, wenn sie im Papierkorb gelandet ist.
    func moveToTrash(_ file: URL) -> Bool {
        let confirm = NSAlert()
        confirm.messageText = "„\(file.lastPathComponent)“ in den Papierkorb legen?"
        confirm.informativeText = "Du kannst die Datei im Finder aus dem Papierkorb zurücklegen."
        confirm.addButton(withTitle: "In den Papierkorb").hasDestructiveAction = true
        confirm.addButton(withTitle: "Abbrechen")
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        } catch {
            // Dateien in iCloud-Ordnern (z. B. „Dokumente“ mit iCloud-Sync) darf Platzwart oft nicht
            // selbst in den Papierkorb legen. Dann übernimmt der Finder – macOS fragt einmal nach Erlaubnis.
            if let finderError = trashWithFinder(file) {
                showError("In den Papierkorb legen hat nicht geklappt. \(finderError)",
                          title: "Nicht in den Papierkorb gelegt")
                return false
            }
        }
        looseFiles.removeAll { $0.url == file }
        return true
    }

    /// Bittet den Finder, die Datei in den Papierkorb zu legen. Gibt bei Erfolg `nil` zurück, sonst den Grund.
    private func trashWithFinder(_ file: URL) -> String? {
        let path = file.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"\(path)\" as alias)")?
            .executeAndReturnError(&error)
        if !FileManager.default.fileExists(atPath: file.path) { return nil }
        if (error?[NSAppleScript.errorNumber] as? Int) == -1743 {
            return "Platzwart darf den Finder nicht steuern. Erlaube es unter Systemeinstellungen → Datenschutz & Sicherheit → Automation → Platzwart → Finder."
        }
        return (error?[NSAppleScript.errorMessage] as? String) ?? "Der Finder konnte die Datei nicht in den Papierkorb legen."
    }

    private func showError(_ text: String, title: String = "Nicht verschoben") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}

// MARK: - „Wohin mit …?“

struct PlacementPanel: View {
    @EnvironmentObject var store: FolderStore
    @EnvironmentObject var placement: PlacementController
    let file: URL
    /// Wird aufgerufen, wenn du fertig bist – egal ob verschoben oder nicht.
    let onDone: () -> Void

    @State private var suggestions: [PlacementIndex.Suggestion] = []
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wohin mit „\(file.lastPathComponent)“?")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text("Liegt in: \(file.deletingLastPathComponent().lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.result == nil {
                Text("Platzwart durchsucht deine Ordner noch. Gleich gibt es Vorschläge.")
                    .foregroundStyle(.secondary)
            } else if suggestions.isEmpty {
                Text("Kein passender Ordner gefunden. Wähl mit „Anderer Ordner …“ selbst einen aus.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passt wahrscheinlich in:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { position, suggestion in
                        SuggestionChoice(suggestion: suggestion, isBest: position == 0,
                                         isSelected: selected == suggestion.id)
                            .onTapGesture { selected = suggestion.id }
                    }
                }
            }

            HStack {
                Button("Nicht verschieben") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    if placement.moveToTrash(file) { store.forget(file); onDone() }
                } label: {
                    Label("In den Papierkorb", systemImage: "trash")
                }
                Spacer()
                Button("Anderer Ordner …") {
                    let start = suggestions.first { $0.id == selected }.map { URL(fileURLWithPath: $0.folder.path) }
                    if placement.moveToChosenFolder(file, startingAt: start) { store.forget(file); onDone() }
                }
                Button("Hierhin verschieben") {
                    guard let choice = suggestions.first(where: { $0.id == selected }) else { return }
                    if placement.move(file, to: URL(fileURLWithPath: choice.folder.path)) { store.forget(file); onDone() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 720)
        .onAppear {
            suggestions = placement.suggestions(for: file, index: store.result?.index)
            selected = suggestions.first?.id
        }
    }
}

struct SuggestionChoice: View {
    let suggestion: PlacementIndex.Suggestion
    let isBest: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(PlacementIndex.lastComponent(suggestion.folder.display))
                        .font(.body.weight(.semibold))
                    if isBest {
                        Text("bester Treffer")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.3), in: Capsule())
                    }
                }
                Text(suggestion.folder.display)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !suggestion.reason.isEmpty {
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: suggestion.folder.path))
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Ordner im Finder ansehen")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - „Liegt noch rum“

struct LooseListSheet: View {
    @EnvironmentObject var placement: PlacementController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let file = selected {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        selected = nil
                    } label: {
                        Label("Zurück zur Liste", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .padding([.top, .horizontal], 20)
                    PlacementPanel(file: file) { selected = nil }
                }
            } else {
                list
            }
        }
        .task { placement.loadLooseFiles() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Liegt noch rum").font(.title3.weight(.semibold))
                    Text(placement.isLoadingLoose ? "Wird geladen …"
                         : "\(placement.looseFiles.count) Dateien in Downloads und auf dem Schreibtisch. Klick eine an, um zu fragen, wohin sie gehört.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if !placement.blockedFolders.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kein Zugriff auf \(placement.blockedFolders.joined(separator: " und "))")
                            .font(.callout.weight(.semibold))
                        Text("macOS hat Platzwart den Zugriff noch nicht erlaubt. Erlaube ihn unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner → Platzwart, und öffne die Liste dann neu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Systemeinstellungen öffnen") { PlacementController.openPrivacySettings() }
                            .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            List(placement.looseFiles) { file in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(details(file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wohin damit?") { selected = file.url }
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { selected = file.url }
            }
            .listStyle(.inset)
        }
        .padding(20)
        .frame(width: 640, height: 540)
    }

    private func details(_ file: LooseFile) -> String {
        var parts = [file.source, Recommendations.bytes(file.size)]
        if let date = file.modified { parts.append(date.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}
