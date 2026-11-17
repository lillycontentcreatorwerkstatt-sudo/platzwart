import AppKit
import Foundation

final class FolderStore: ObservableObject {
    @Published var result: ScanResult?
    @Published var isScanning = false
    @Published var scannedFiles = 0
    @Published var customPaths: [String] {
        didSet { UserDefaults.standard.set(customPaths, forKey: Self.customKey) }
    }

    private static let customKey = "eigeneOrdner"
    /// Dateien, die während eines laufenden Scans verschoben oder weggeworfen wurden.
    private var forgottenDuringScan = Set<String>()

    init() {
        customPaths = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
        loadCache()
    }

    // MARK: - Sofortstart: letztes Ergebnis merken

    /// Liegt nur auf diesem Mac, unter ~/Library/Application Support/Platzwart.
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Platzwart/letzter-scan.json")
    }

    private func loadCache() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: Self.cacheURL),
                  let cached = try? JSONDecoder().decode(ScanResult.self, from: data) else { return }
            DispatchQueue.main.async {
                if self?.result == nil { self?.result = cached }
            }
        }
    }

    private static func saveCache(_ result: ScanResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Standardorte, die es auf jedem Mac gibt, plus selbst hinzugefügte Ordner.
    func locations() -> [ScanLocation] {
        let fm = FileManager.default
        var list: [ScanLocation] = []
        if let url = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            list.append(ScanLocation(name: "Schreibtisch", url: url))
        }
        if let url = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            list.append(ScanLocation(name: "Dokumente", url: url))
        }
        if let url = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            list.append(ScanLocation(name: "Downloads", url: url, isDownloads: true))
        }
        let iCloud = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) {
            list.append(ScanLocation(name: "iCloud Drive", url: iCloud))
        }
        for path in customPaths where fm.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            list.append(ScanLocation(name: url.lastPathComponent, url: url, isCustom: true))
        }
        return list
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        scannedFiles = 0
        forgottenDuringScan = []
        let locations = locations()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanner = FolderScanner()
            scanner.onProgress = { count in
                DispatchQueue.main.async { self?.scannedFiles = count }
            }
            let scanned = scanner.run(locations)
            DispatchQueue.main.async {
                guard let self else { return }
                let result = Self.removing(self.forgottenDuringScan, from: scanned)
                self.result = result
                self.isScanning = false
                DispatchQueue.global(qos: .utility).async { Self.saveCache(result) }
                // Was während des Durchlaufs im Finder gelöscht wurde, gleich wieder herausnehmen.
                self.removeMissing()
            }
        }
    }

    /// Nimmt eine verschobene oder weggeworfene Datei sofort aus den Empfehlungen, ohne neu zu scannen.
    func forget(_ url: URL) {
        if isScanning { forgottenDuringScan.insert(url.path) }
        guard let current = result else { return }
        let updated = Self.removing([url.path], from: current)
        result = updated
        DispatchQueue.global(qos: .utility).async { Self.saveCache(updated) }
    }

    /// Nimmt Ordner und Dateien heraus, die es nicht mehr gibt (z. B. im Finder gelöscht).
    /// Geht schnell, weil nur geprüft wird, ob die angezeigten Pfade noch existieren.
    func removeMissing() {
        guard let current = result else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var gone = Set<String>()
            let files = current.largeFiles + current.oldDownloads + current.duplicates.flatMap { $0 }
            for file in files where !fm.fileExists(atPath: file.url.path) { gone.insert(file.url.path) }
            var changed = !gone.isEmpty
            var roots = current.roots.compactMap { Self.pruned($0, changed: &changed) }
            guard changed else { return }
            let biggest = roots.map(\.size).max() ?? 0
            for i in roots.indices { roots[i].share = biggest > 0 ? Double(roots[i].size) / Double(biggest) : 0 }
            DispatchQueue.main.async {
                // Ist inzwischen ein neuer Durchlauf fertig geworden, gilt dessen Ergebnis.
                guard let self, let latest = self.result, latest.scannedAt == current.scannedAt else { return }
                var updated = Self.removing(gone, from: latest)
                updated.roots = roots
                self.result = updated
                DispatchQueue.global(qos: .utility).async { Self.saveCache(updated) }
            }
        }
    }

    /// Entfernt verschwundene Unterordner und zieht ihre Größe von den Elternordnern ab. `nil`, wenn der Ordner selbst fehlt.
    private static func pruned(_ node: FolderNode, changed: inout Bool) -> FolderNode? {
        guard FileManager.default.fileExists(atPath: node.url.path) else { changed = true; return nil }
        guard let children = node.children else { return node }
        let kept = children.compactMap { pruned($0, changed: &changed) }
        var updated = node
        updated.size -= children.reduce(Int64(0)) { $0 + $1.size } - kept.reduce(Int64(0)) { $0 + $1.size }
        updated.fileCount -= children.reduce(0) { $0 + $1.fileCount } - kept.reduce(0) { $0 + $1.fileCount }
        updated.children = kept.isEmpty ? nil : kept.map { child in
            var child = child
            child.share = updated.size > 0 ? Double(child.size) / Double(updated.size) : 0
            return child
        }
        return updated
    }

    private static func removing(_ paths: Set<String>, from result: ScanResult) -> ScanResult {
        guard !paths.isEmpty else { return result }
        var updated = result
        updated.largeFiles.removeAll { paths.contains($0.url.path) }
        updated.oldDownloads.removeAll { paths.contains($0.url.path) }
        updated.duplicates = updated.duplicates
            .map { group in group.filter { !paths.contains($0.url.path) } }
            .filter { $0.count > 1 }
        return updated
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Hinzufügen"
        panel.message = "Welchen Ordner soll Platzwart zusätzlich anzeigen?"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !customPaths.contains(url.path) else { return }
        customPaths.append(url.path)
        rescan()
    }

    func removeFolder(_ url: URL) {
        customPaths.removeAll { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == url.path }
        rescan()
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
