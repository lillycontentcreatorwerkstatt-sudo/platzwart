import Foundation

/// Merkt sich beim Scan, welche Dateinamen und Dateitypen in welchem Ordner liegen,
/// um für herumliegende Dateien passende Ordner vorzuschlagen.
struct PlacementIndex: Codable {
    struct Folder: Codable {
        let path: String
        /// Lesbarer Pfad, z. B. „Dokumente › Finanzen › Telekom“
        let display: String
        var lastChanged: Date?
    }

    struct Posting: Codable {
        let folder: Int
        let count: Int
        let example: String
    }

    var folders: [Folder] = []
    /// Wort aus Dateinamen → Ordner, in denen es vorkommt
    var fileTokens: [String: [Posting]] = [:]
    /// Wort aus dem Ordnerpfad → Ordner
    var nameTokens: [String: [Int]] = [:]
    /// Dateiendung → Ordner mit Dateien dieses Typs
    var extensions: [String: [Posting]] = [:]

    // MARK: - Aufbau

    mutating func addFolder(path: String, display: String) -> Int {
        let id = folders.count
        folders.append(Folder(path: path, display: display))
        for token in Set(Self.tokens(display)) {
            nameTokens[token, default: []].append(id)
        }
        return id
    }

    mutating func addFiles(folder: Int, tokens: [String: (Int, String)], extensions exts: [String: (Int, String)]) {
        for (token, value) in tokens {
            fileTokens[token, default: []].append(Posting(folder: folder, count: value.0, example: value.1))
        }
        for (ext, value) in exts {
            extensions[ext, default: []].append(Posting(folder: folder, count: value.0, example: value.1))
        }
    }

    // MARK: - Vorschläge

    struct Suggestion: Identifiable {
        var id: String { folder.path }
        let folder: Folder
        let reason: String
    }

    private struct Hit {
        var score: Double = 0
        var files = 0
        var example: String?
        var nameMatch = false
        var sameType = 0
    }

    func suggest(query: String, fileExtension: String?, limit: Int = 5) -> [Suggestion] {
        let queryTokens = Array(Set(Self.tokens(query)))
        let ext = fileExtension?.lowercased()
        guard !queryTokens.isEmpty || ext != nil, !folders.isEmpty else { return [] }

        let total = Double(folders.count)
        var hits: [Int: Hit] = [:]

        for q in queryTokens {
            var best: [Int: (score: Double, files: Int, example: String)] = [:]
            for key in matchingKeys(q, in: fileTokens) {
                guard let postings = fileTokens[key] else { continue }
                let idf = log(total / Double(1 + postings.count)) + 1
                for p in postings {
                    let value = idf * (1 + log(Double(p.count)))
                    if value > (best[p.folder]?.score ?? 0) {
                        best[p.folder] = (value, p.count, p.example)
                    }
                }
            }
            for (folder, b) in best {
                hits[folder, default: Hit()].score += b.score
                hits[folder, default: Hit()].files += b.files
                if hits[folder]?.example == nil { hits[folder]?.example = b.example }
            }

            var nameBest: [Int: Double] = [:]
            for key in matchingKeys(q, in: nameTokens) {
                guard let ids = nameTokens[key] else { continue }
                let idf = log(total / Double(1 + ids.count)) + 1
                for id in ids { nameBest[id] = max(nameBest[id] ?? 0, idf) }
            }
            for (id, idf) in nameBest {
                // Passt der eigene Ordnername (nicht nur ein übergeordneter), zählt das mehr.
                let own = Self.tokens(Self.lastComponent(folders[id].display)).contains { $0.hasPrefix(q) }
                hits[id, default: Hit()].score += idf * (own ? 2.5 : 1.5)
                hits[id, default: Hit()].nameMatch = true
            }
        }

        if let ext, let postings = extensions[ext] {
            for p in postings where queryTokens.isEmpty || hits[p.folder] != nil {
                hits[p.folder, default: Hit()].score += 0.6 * log(1 + Double(p.count))
                hits[p.folder, default: Hit()].sameType = p.count
                if queryTokens.isEmpty && hits[p.folder]?.example == nil { hits[p.folder]?.example = p.example }
            }
        }

        let recent = Date().addingTimeInterval(-180 * 24 * 3600)
        let ranked = hits.map { id, hit -> (Int, Hit) in
            var hit = hit
            if let changed = folders[id].lastChanged, changed > recent { hit.score *= 1.15 }
            // Hauptordner wie „Dokumente“ sind als Ablageort zu ungenau.
            if !folders[id].display.contains(" › ") { hit.score *= 0.6 }
            // Liegen dort schon Dateien desselben Typs, passt der Ordner deutlich besser.
            if ext != nil, !queryTokens.isEmpty { hit.score *= hit.sameType > 0 ? 1.5 : 0.5 }
            return (id, hit)
        }
        .sorted { $0.1.score > $1.1.score }
        .prefix(limit)

        return ranked.map { id, hit in
            Suggestion(folder: folders[id], reason: Self.reason(for: hit, ext: ext))
        }
    }

    private func matchingKeys<V>(_ q: String, in dict: [String: V]) -> [String] {
        var keys: [String] = dict[q] != nil ? [q] : []
        // Teilwörter beim Tippen: „rechn“ findet „rechnung“ und „rechnungen“
        if q.count >= 4 {
            for key in dict.keys where key != q && key.hasPrefix(q) {
                keys.append(key)
                if keys.count >= 40 { break }
            }
        }
        return keys
    }

    private static func reason(for hit: Hit, ext: String?) -> String {
        var parts: [String] = []
        if hit.nameMatch { parts.append("Ordnername passt") }
        if hit.files > 0 {
            let similar = hit.files == 1 ? "1 ähnliche Datei" : "\(hit.files) ähnliche Dateien"
            if let example = hit.example {
                parts.append("\(similar), z. B. „\(shortName(example))“")
            } else {
                parts.append(similar)
            }
        }
        if hit.sameType > 0, let ext, hit.files == 0 {
            let type = ext.uppercased()
            parts.append(hit.sameType == 1 ? "hier liegt schon eine \(type)-Datei" : "hier liegen schon \(hit.sameType) \(type)-Dateien")
            if !hit.nameMatch, let example = hit.example { parts.append("z. B. „\(shortName(example))“") }
        }
        return parts.joined(separator: " · ")
    }

    /// Zeilenumbrüche entfernen und sehr lange Namen kürzen.
    private static func shortName(_ name: String) -> String {
        let flat = name.components(separatedBy: .newlines).joined(separator: " ")
        guard flat.count > 48 else { return flat }
        return String(flat.prefix(30)) + "…" + String(flat.suffix(15))
    }

    // MARK: - Wörter zerlegen

    private static let stopWords: Set<String> = [
        "und", "der", "die", "das", "den", "dem", "des", "mit", "von", "fur", "auf", "ein", "eine",
        "the", "and", "for", "with", "final", "kopie", "copy", "neu", "new"
    ]

    /// „Rechnung_Telekom-März 2024.pdf“ → ["rechnung", "telekom", "marz"]
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !stopWords.contains($0) }
    }

    static func lastComponent(_ display: String) -> String {
        display.components(separatedBy: " › ").last ?? display
    }
}
