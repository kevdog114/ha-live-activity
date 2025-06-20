//
//  HaLiveNotificationsApp.swift
//  HaLiveNotifications
//
//  Created by Kevin Schaefer on 6/20/25.
//

import SwiftUI
import SwiftData

@main
struct HaLiveNotificationsApp: App {
    // Initialize AppState as a StateObject or just a regular object
    // depending on how it's managed. If AppState uses @Observable,
    // it doesn't need to be @StateObject here if it's passed via .environment()
    @State private var appState = AppState() // If AppState is @Observable

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
                HomeAssistantConnection.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                    .environment(appState) // Inject AppState into the environment
        }
            .modelContainer(sharedModelContainer) // This provides the modelContext
    }
}
