import SwiftUI

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var store: FolderStore
    @EnvironmentObject var placement: PlacementController

    var body: some View {
        VStack(spacing: 0) {
            StatsBar()
                .padding(16)
            Divider()
            HSplitView {
                FolderTreeView()
                    .frame(minWidth: 460, idealWidth: 600)
                RecommendationsView()
                    .frame(minWidth: 340, idealWidth: 380)
            }
            Divider()
            BottomBar()
        }
        .toolbar {
            ToolbarItem {
                Button { store.addFolder() } label: {
                    Label("Ordner hinzufügen", systemImage: "folder.badge.plus")
                }
                .help("Weiteren Ordner zur Übersicht hinzufügen")
            }
            ToolbarItem {
                Button {
                    stats.readDisk()
                    store.rescan()
                } label: {
                    Label("Neu scannen", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
                .help("Ordner neu durchsuchen")
            }
        }
        .sheet(item: $placement.pendingFile) { pending in
            PlacementPanel(file: pending.url) { placement.pendingFile = nil }
                .environmentObject(store)
                .environmentObject(placement)
        }
        .sheet(isPresented: $placement.showLooseList) {
            LooseListSheet()
                .environmentObject(store)
                .environmentObject(placement)
        }
        .task {
            // Das letzte Ergebnis wird sofort gezeigt, aktualisiert wird im Hintergrund.
            store.rescan()
        }
    }
}

// MARK: - Knöpfe unten

struct BottomBar: View {
    @EnvironmentObject var placement: PlacementController

    var body: some View {
        HStack(spacing: 10) {
            Button { placement.chooseFile() } label: {
                Label("Datei einsortieren …", systemImage: "doc.badge.arrow.up")
            }
            .help("Datei auswählen und fragen, in welchen Ordner sie gehört")
            Button { placement.showLooseList = true } label: {
                Label("Liegt noch rum", systemImage: "tray.full")
            }
            .help("Dateien aus Downloads und vom Schreibtisch ansehen")

            if let moved = placement.lastMoved {
                Label("„\(moved.name)“ ist jetzt in \(moved.folder.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Zeigen") { NSWorkspace.shared.open(moved.folder) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Spacer()
            Text("Platzwart löscht nichts und verschiebt nur, wenn du es sagst.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Auslastung

struct StatsBar: View {
    @EnvironmentObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 16) {
            GaugeCard(
                title: "Speicher",
                symbol: "internaldrive",
                fraction: stats.diskUsedFraction,
                detail: "\(Recommendations.bytes(stats.diskFree)) frei von \(Recommendations.bytes(stats.diskTotal))"
            )
            GaugeCard(
                title: "Arbeitsspeicher",
                symbol: "memorychip",
                fraction: 1 - stats.memAvailable,
                detail: "Speicherdruck \(Recommendations.percent(1 - stats.memAvailable)) · \(memory(stats.memUsed)) von \(memory(stats.memTotal)) belegt",
                valueText: pressure.text,
                colorOverride: pressure.color
            )
            .help("Wie die Aktivitätsanzeige: Der Speicherdruck zeigt, ob der Arbeitsspeicher wirklich knapp wird. Dass macOS viel belegt, ist normal.")
            GaugeCard(
                title: "Prozessor",
                symbol: "cpu",
                fraction: stats.cpu,
                detail: "Auslastung gerade"
            )
        }
    }

    private var pressure: (text: String, color: Color) {
        switch stats.memPressureLevel {
        case 4...: return ("Zu wenig", .red)
        case 2...: return ("Wird eng", .orange)
        default: return ("Alles gut", .green)
        }
    }

    private func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

struct GaugeCard: View {
    let title: String
    let symbol: String
    let fraction: Double
    let detail: String
    var valueText: String?
    var colorOverride: Color?

    private var color: Color {
        colorOverride ?? (fraction >= 0.9 ? .red : fraction >= 0.75 ? .orange : .green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
                Text(valueText ?? Recommendations.percent(fraction))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Ordnerbaum

struct FolderTreeView: View {
    @EnvironmentObject var store: FolderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ordner").font(.headline)
                Spacer()
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Durchsuche … \(store.scannedFiles) Dateien")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let roots = store.result?.roots {
                List {
                    OutlineGroup(roots, children: \.children) { node in
                        FolderRow(node: node)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
                HStack { Spacer(); Text("Ordner werden durchsucht …").foregroundStyle(.secondary); Spacer() }
                Spacer()
            }
        }
    }
}

struct FolderRow: View {
    @EnvironmentObject var store: FolderStore
    let node: FolderNode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isCustom ? "folder.badge.person.crop" : "folder")
                .foregroundStyle(.blue)
            // Der Name bekommt den ganzen restlichen Platz und wird nur gekürzt, wenn es wirklich eng wird.
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(node.name)
            // Feste Spalten rechts: stehen in jeder Ebene untereinander und werden nie abgeschnitten.
            HStack(spacing: 8) {
                Text(node.lastChanged.map(Self.shortAge) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                    .help("Zuletzt geändert")
                Text(Recommendations.bytes(node.size))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                    .help("\(node.fileCount) Dateien")
                ShareBar(share: node.share)
                    .frame(width: 44, height: 6)
            }
            .fixedSize()
        }
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FolderStore.revealInFinder(node.url) }
        .contextMenu {
            Button("Im Finder zeigen") { FolderStore.revealInFinder(node.url) }
            if node.isCustom {
                Button("Aus Übersicht entfernen") { store.removeFolder(node.url) }
            }
        }
    }

    /// Kurzes Alter: „heute“, „5 Std.“, „3 Wo.“, „11 Mon.“, „2 J.“
    static func shortAge(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        let hours = seconds / 3600
        let days = hours / 24
        switch days {
        case ..<(1.0 / 24): return "gerade"
        case ..<1: return "\(Int(hours)) Std."
        case ..<14: return "\(Int(days)) Tg."
        case ..<60: return "\(Int(days / 7)) Wo."
        case ..<365: return "\(Int(days / 30)) Mon."
        default: return "\(Int(days / 365)) J."
        }
    }
}

struct ShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.blue).frame(width: geo.size.width * min(max(share, 0), 1))
            }
        }
    }
}

// MARK: - Empfehlungen

struct RecommendationsView: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var store: FolderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Empfehlungen").font(.headline)
                Spacer()
                if let date = store.result?.scannedAt {
                    Text("Stand \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let result = store.result {
                let items = Recommendations.build(result: result, diskTotal: stats.diskTotal, diskFree: stats.diskFree)
                if items.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.green)
                        Text("Alles im grünen Bereich.")
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(items) { item in
                        RecommendationCard(item: item)
                    }
                    .listStyle(.inset)
                }
            } else {
                Spacer()
            }

        }
    }
}

struct RecommendationCard: View {
    @EnvironmentObject var placement: PlacementController
    let item: Recommendation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(item.title, systemImage: item.level == .dringend ? "exclamationmark.triangle.fill" : "lightbulb")
                .font(.body.weight(.semibold))
                .foregroundStyle(item.level == .dringend ? .red : .primary)
            Text(item.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !item.files.isEmpty {
                Button {
                    expanded.toggle()
                } label: {
                    Label(expanded ? "Dateien ausblenden" : "Dateien anzeigen (\(item.files.count))",
                          systemImage: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                if expanded {
                    ForEach(item.files) { file in
                        HStack {
                            Text(file.url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(file.url.path)
                            Spacer()
                            Text(Recommendations.bytes(file.size))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                FolderStore.revealInFinder(file.url)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Im Finder zeigen")
                            Button("Wohin damit?") {
                                placement.pendingFile = PendingFile(url: file.url)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        .font(.callout)
                        .padding(.leading, 20)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if !item.files.isEmpty { expanded.toggle() }
        }
    }
}
