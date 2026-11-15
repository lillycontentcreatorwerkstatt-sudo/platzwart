import Foundation

struct Recommendation: Identifiable {
    enum Level { case hinweis, dringend }

    /// Feste ID je Regel, damit aufgeklappte Listen beim Aktualisieren offen bleiben.
    let id: String
    let level: Level
    let title: String
    let detail: String
    var files: [FileInfo] = []
}

enum Recommendations {
    static let maxFilesShown = 10

    static func build(result: ScanResult, diskTotal: Int64, diskFree: Int64) -> [Recommendation] {
        var list: [Recommendation] = []

        // 1. Speicher fast voll
        if diskTotal > 0 {
            let used = Double(diskTotal - diskFree) / Double(diskTotal)
            if used >= 0.8 {
                list.append(Recommendation(
                    id: "speicher",
                    level: used >= 0.9 ? .dringend : .hinweis,
                    title: "Speicher zu \(percent(used)) voll",
                    detail: "Noch \(bytes(diskFree)) frei. Ab etwa 90 % wird der Mac spürbar langsamer – Aufräumen lohnt sich."
                ))
            }
        }

        // 2. Alte Downloads
        let oldSize = result.oldDownloads.reduce(Int64(0)) { $0 + $1.size }
        if oldSize >= 500_000_000 {
            let days = Int(FolderScanner.oldDownloadDays)
            list.append(Recommendation(
                    id: "downloads",
                level: .hinweis,
                title: "Downloads: \(bytes(oldSize)) älter als \(days) Tage",
                detail: "\(result.oldDownloads.count) Dateien wurden seit über \(days) Tagen nicht geändert. Ausmisten oder in einen passenden Ordner verschieben.",
                files: Array(result.oldDownloads.prefix(maxFilesShown))
            ))
        }

        // 3. Sehr große Dateien
        if !result.largeFiles.isEmpty {
            let total = result.largeFiles.reduce(Int64(0)) { $0 + $1.size }
            list.append(Recommendation(
                    id: "gross",
                level: .hinweis,
                title: "\(result.largeFiles.count) Dateien über 1 GB",
                detail: "Zusammen \(bytes(total)). Brauchst du die noch hier, oder können sie auf eine externe Festplatte?",
                files: Array(result.largeFiles.prefix(maxFilesShown))
            ))
        }

        // 4. Vermutlich doppelte Dateien
        if !result.duplicates.isEmpty {
            let wasted = result.duplicates.reduce(Int64(0)) { sum, group in
                sum + (group.first?.size ?? 0) * Int64(group.count - 1)
            }
            list.append(Recommendation(
                    id: "doppelt",
                level: .hinweis,
                title: "\(result.duplicates.count) Dateien vermutlich doppelt",
                detail: "Gleicher Name und gleiche Größe an mehreren Stellen. Möglicher Gewinn: \(bytes(wasted)). Vor dem Löschen kurz prüfen.",
                files: Array(result.duplicates.prefix(maxFilesShown).flatMap { $0 })
            ))
        }

        return list
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}
