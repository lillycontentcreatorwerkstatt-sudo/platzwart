import Foundation

struct FolderNode: Identifiable, Codable {
    var id: String { url.path }
    let url: URL
    let name: String
    var size: Int64 = 0
    var fileCount = 0
    var lastChanged: Date?
    /// Anteil an der Größe des übergeordneten Ordners (0…1), für den Balken.
    var share: Double = 0
    var isCustom = false
    var children: [FolderNode]?
}

struct FileInfo: Identifiable, Codable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modified: Date?
}

struct ScanResult: Codable {
    var roots: [FolderNode]
    var largeFiles: [FileInfo]
    var duplicates: [[FileInfo]]
    var oldDownloads: [FileInfo]
    var index: PlacementIndex
    var scannedAt: Date
}

struct ScanLocation {
    let name: String
    let url: URL
    var isDownloads = false
    var isCustom = false
}

/// Durchläuft Ordner und sammelt Größen. Liest nur, verändert nie etwas.
final class FolderScanner {
    static let largeFileLimit: Int64 = 1_000_000_000      // 1 GB
    static let duplicateMinSize: Int64 = 1_000_000        // 1 MB
    static let oldDownloadDays: Double = 90
    private static let treeDepth = 4                       // so tief wird der Baum angezeigt

    var onProgress: ((Int) -> Void)?

    private let fm = FileManager.default
    private let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey,
        .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey
    ]
    private let oldCutoff = Date().addingTimeInterval(-oldDownloadDays * 24 * 3600)
    private var seen = Set<String>()
    private var largeFiles: [FileInfo] = []
    private var byNameAndSize: [String: [FileInfo]] = [:]
    private var oldDownloads: [FileInfo] = []
    private var fileCounter = 0
    private var index = PlacementIndex()
    private var rootPath = ""
    private var rootName = ""

    func run(_ locations: [ScanLocation]) -> ScanResult {
        var roots: [FolderNode] = []
        for location in locations {
            let url = location.url.resolvingSymlinksInPath()
            rootPath = url.path
            rootName = location.name
            var node = scanFolder(url, name: location.name, depth: 0, inDownloads: location.isDownloads,
                                  quiet: false, inProject: false)
            node.isCustom = location.isCustom
            roots.append(node)
        }
        let biggest = roots.map(\.size).max() ?? 0
        for i in roots.indices {
            roots[i].share = biggest > 0 ? Double(roots[i].size) / Double(biggest) : 0
        }
        let duplicates = byNameAndSize.values
            .filter { $0.count > 1 }
            .sorted { wasted($0) > wasted($1) }
        return ScanResult(
            roots: roots,
            largeFiles: largeFiles.sorted { $0.size > $1.size },
            duplicates: duplicates,
            oldDownloads: oldDownloads.sorted { $0.size > $1.size },
            index: index,
            scannedAt: Date()
        )
    }

    private func wasted(_ group: [FileInfo]) -> Int64 {
        (group.first?.size ?? 0) * Int64(group.count - 1)
    }

    /// `quiet`: Größe zählt mit, aber keine Empfehlungen (versteckte Ordner, Technik-Ordner in Programmierprojekten).
    private func scanFolder(_ url: URL, name: String, depth: Int, inDownloads: Bool,
                            quiet: Bool, inProject: Bool) -> FolderNode {
        // Hilfsobjekte von macOS nach jedem Ordner freigeben, sonst wächst der Speicher beim Scan stark an.
        autoreleasepool {
            scanFolderContents(url, name: name, depth: depth, inDownloads: inDownloads,
                               quiet: quiet, inProject: inProject)
        }
    }

    private func scanFolderContents(_ url: URL, name: String, depth: Int, inDownloads: Bool,
                                    quiet: Bool, inProject: Bool) -> FolderNode {
        var node = FolderNode(url: url, name: name)
        var subfolders: [FolderNode] = []
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))) ?? []
        let inProject = inProject || Self.isCodeProject(items)
        // Für die Ordnervorschläge merken – nicht für Downloads (dort will man nichts ablegen) und nicht für Technik-Ordner.
        let indexable = !quiet && !inDownloads
        let folderID = indexable ? index.addFolder(path: url.path, display: displayPath(url)) : -1
        var folderTokens: [String: (Int, String)] = [:]
        var folderExtensions: [String: (Int, String)] = [:]

        for item in items {
            guard let v = try? item.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            let hidden = v.isHidden == true

            if v.isDirectory == true && v.isPackage != true {
                let folderName = item.lastPathComponent
                let technical = Self.alwaysTechnical.contains(folderName)
                    || (inProject && Self.projectTechnical.contains(folderName))
                let child = scanFolder(item, name: folderName, depth: depth + 1, inDownloads: inDownloads,
                                       quiet: quiet || hidden || technical, inProject: inProject)
                node.size += child.size
                node.fileCount += child.fileCount
                node.lastChanged = latest(node.lastChanged, child.lastChanged)
                if depth < Self.treeDepth && !hidden { subfolders.append(child) }
            } else {
                let isPackage = v.isDirectory == true
                let size = isPackage ? packageSize(item) : Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                node.size += size
                node.fileCount += 1
                node.lastChanged = latest(node.lastChanged, v.contentModificationDate)
                fileCounter += 1
                if fileCounter % 2000 == 0 { onProgress?(fileCounter) }
                if !hidden && !quiet {
                    record(FileInfo(url: item, size: size, modified: v.contentModificationDate),
                           isPackage: isPackage, inDownloads: inDownloads)
                }
                if indexable && !hidden {
                    let fileName = item.lastPathComponent
                    for token in Set(PlacementIndex.tokens(item.deletingPathExtension().lastPathComponent)) {
                        let current = folderTokens[token]
                        folderTokens[token] = ((current?.0 ?? 0) + 1, current?.1 ?? fileName)
                    }
                    let ext = item.pathExtension.lowercased()
                    if !ext.isEmpty {
                        let current = folderExtensions[ext]
                        folderExtensions[ext] = ((current?.0 ?? 0) + 1, current?.1 ?? fileName)
                    }
                }
            }
        }

        if indexable {
            index.addFiles(folder: folderID, tokens: folderTokens, extensions: folderExtensions)
            index.folders[folderID].lastChanged = node.lastChanged
        }

        for i in subfolders.indices {
            subfolders[i].share = node.size > 0 ? Double(subfolders[i].size) / Double(node.size) : 0
        }
        subfolders.sort { $0.size > $1.size }
        node.children = subfolders.isEmpty ? nil : subfolders
        return node
    }

    /// Programmierprojekte enthalten viele technisch bedingte Kopien (node_modules, Build-Ordner).
    /// Diese Ordner zählen zur Größe, bekommen aber keine Empfehlungen.
    private static let alwaysTechnical: Set<String> = ["node_modules", "DerivedData", "Pods", "__pycache__", "venv"]
    private static let projectTechnical: Set<String> = ["bin", "obj", "build", "dist", "artifacts", "target", "out", "vendor"]
    private static let codeProjectMarkers: Set<String> = [
        ".git", "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "go.mod", "pom.xml", "build.gradle"
    ]
    private static let codeProjectExtensions: Set<String> = ["sln", "csproj", "xcodeproj", "xcworkspace"]

    static func isCodeProject(_ items: [URL]) -> Bool {
        items.contains {
            codeProjectMarkers.contains($0.lastPathComponent) || codeProjectExtensions.contains($0.pathExtension)
        }
    }

    private func record(_ file: FileInfo, isPackage: Bool, inDownloads: Bool) {
        let isLarge = file.size >= Self.largeFileLimit
        let isDuplicateCandidate = !isPackage && file.size >= Self.duplicateMinSize
        let isOldDownload = inDownloads && (file.modified.map { $0 < oldCutoff } ?? false)
        guard isLarge || isDuplicateCandidate || isOldDownload else { return }
        // Liegt ein Ordner in mehreren Bereichen (z. B. eigener Ordner in Dokumente), nur einmal zählen.
        guard seen.insert(file.url.path).inserted else { return }

        if isLarge { largeFiles.append(file) }
        if isDuplicateCandidate {
            let key = Self.normalizedName(file.url) + "|\(file.size)"
            byNameAndSize[key, default: []].append(file)
        }
        if isOldDownload { oldDownloads.append(file) }
    }

    private func packageSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let sizeKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: sizeKeys) else { return 0 }
        for case let file as URL in walker {
            autoreleasepool {
                if let v = try? file.resourceValues(forKeys: Set(sizeKeys)) {
                    total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                }
            }
        }
        return total
    }

    /// „/Users/x/Documents/Finanzen/Telekom“ → „Dokumente › Finanzen › Telekom“
    private func displayPath(_ url: URL) -> String {
        let relative = url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.path
        let parts = [rootName] + relative.split(separator: "/").map(String.init)
        return parts.joined(separator: " › ")
    }

    private func latest(_ a: Date?, _ b: Date?) -> Date? {
        guard let a else { return b }
        guard let b else { return a }
        return max(a, b)
    }

    /// "Rechnung 2.pdf", "Rechnung (1).pdf" und "Rechnung Kopie.pdf" gelten als gleicher Name.
    static func normalizedName(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        var base = url.deletingPathExtension().lastPathComponent.lowercased()
        let patterns = [#"\s\(\d+\)$"#, #"\s(kopie|copy)(\s\d+)?$"#, #"\s\d{1,2}$"#]
        for pattern in patterns {
            base = base.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return ext.isEmpty ? base : base + "." + ext
    }
}
