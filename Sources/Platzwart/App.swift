import SwiftUI

@main
struct PlatzwartApp: App {
    @StateObject private var stats = SystemStats()
    @StateObject private var store = FolderStore()
    @StateObject private var placement = PlacementController()

    var body: some Scene {
        WindowGroup("Platzwart") {
            ContentView()
                .environmentObject(stats)
                .environmentObject(store)
                .environmentObject(placement)
                .frame(minWidth: 1000, minHeight: 680)
        }
    }
}
