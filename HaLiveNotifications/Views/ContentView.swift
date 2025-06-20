import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    // To control the presentation of the login view
    @State private var showingLoginView = false

    var body: some View {
        Group { // Use a Group to handle the conditional logic cleanly
            if appState.isLoading {
                ProgressView("Loading...")
            } else if appState.currentConnection != nil {
                // If connected, show the main app content (e.g., LiveActivityListView)
                // For now, let's use the LiveActivityListView if it exists,
                // or a placeholder if it doesn't.
                // Assuming LiveActivityListView exists and is the main view:
                LiveActivityListView()
                    // You might need to pass the HomeAssistantAPIClient or connection details
                    // to LiveActivityListView, or it can access them from AppState.
            } else {
                // Not connected, and not loading.
                // This will trigger the sheet to show once appState.currentConnection is confirmed nil.
                // The login view will be presented as a sheet.
                // A placeholder text or button to trigger login can be here if needed,
                // but the .sheet modifier handles the presentation.
                VStack {
                    Text("Not Connected to Home Assistant")
                        .font(.headline)
                    Button("Connect") {
                        showingLoginView = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }

            }
        }
        .onAppear {
            // Only load if not already loaded or if no connection is set
            if appState.currentConnection == nil && !appState.isLoading {
                appState.loadPersistedConnection(context: modelContext)
            }
        }
        // This watcher ensures that if appState.currentConnection becomes nil AFTER initial load,
        // (e.g. due to a disconnect action), the login view is re-presented.
        // And also handles the initial presentation if no connection is found on load.
        .onChange(of: appState.currentConnection) { oldValue, newValue in
            if newValue == nil && !appState.isLoading {
                showingLoginView = true
            } else if newValue != nil {
                showingLoginView = false // Dismiss if a connection is established
            }
        }
        .onChange(of: appState.isLoading) { _, newIsLoading in
            // If loading finishes and there's no connection, show login.
            if !newIsLoading && appState.currentConnection == nil {
                showingLoginView = true
            }
        }
        .sheet(isPresented: $showingLoginView) {
            // Present HomeAssistantLoginView as a sheet.
            // Pass AppState and modelContext if needed, though they are environment objects.
            HomeAssistantLoginView()
                .environment(appState) // Ensure AppState is available if sheet has its own env scope
                .environment(\.modelContext, modelContext) // Pass model context
        }
    }
}

// Preview needs to be updated to provide AppState and a ModelContainer
#Preview {
    // Create a dummy AppState and ModelContainer for preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HomeAssistantConnection.self, Item.self, configurations: config)
    let appState = AppState()
    // Simulate initial load for different scenarios in preview if needed:
    // appState.isLoading = true
    // appState.currentConnection = HomeAssistantConnection(baseURL: URL(string: "http://example.com")!, accessToken: "fake")
    // appState.loadPersistedConnection(context: container.mainContext)


    return ContentView()
        .modelContainer(container)
        .environment(appState)
}
