// In HaLiveNotifications/Views/LiveActivityListView.swift
// This is a simplified example. A real view would have more robust state management.
import SwiftUI

struct LiveActivityListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext // Added for disconnect

    // State for this view
    @State private var entities: [HAState] = []
    @State private var isLoadingActivities: Bool = false
    @State private var viewError: Error? = nil // Use HAErrors or APIClient.APIError

    var body: some View {
        NavigationView { // Or NavigationStack
            Group {
                if isLoadingActivities {
                    ProgressView("Loading Home Assistant Data...")
                } else if let error = viewError {
                    VStack {
                        Text("Error Loading Data")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Retry") {
                            fetchEntities()
                        }
                        .padding(.top)
                    }
                } else if entities.isEmpty {
                    VStack {
                        Text("No entities found or loaded yet.")
                            .foregroundColor(.gray)
                        Button("Fetch Entities") {
                             fetchEntities()
                         }
                        .padding()
                    }
                } else {
                    List {
                        // Section for general info
                        Section("Connection Info") {
                            if let connection = appState.currentConnection {
                                Text("Connected to: \(connection.instanceName ?? connection.baseURL.absoluteString)")
                                Text("Base URL: \(connection.baseURL.absoluteString)")
                            } else {
                                Text("Not connected.")
                            }
                            Button("Test API: Fetch States") {
                                 fetchEntities()
                             }
                        }

                        // Section for entities
                        Section("Entities (States) - \(entities.count) found") {
                            ForEach(entities) { entity in
                                VStack(alignment: .leading) {
                                    Text(entity.attributes["friendly_name"]?.value as? String ?? entity.entityId)
                                        .font(.headline)
                                    Text("State: \(entity.state)")
                                        .font(.subheadline)
                                    if let lastChanged = entity.attributes["last_changed"]?.value as? String {
                                        Text("Last Changed: \(formattedDate(from: lastChanged) ?? lastChanged)")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Home Assistant Console")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Disconnect") {
                        appState.disconnect(context: modelContext)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { // Explicit refresh button
                        fetchEntities()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoadingActivities || appState.apiClient == nil)
                }
            }
            .onAppear {
                // Fetch data when the view appears if not already loaded and client is available
                if entities.isEmpty && appState.apiClient != nil && !isLoadingActivities {
                    fetchEntities()
                }
            }
            // Optional: Refresh when connection status changes and we get a new client
            .onChange(of: appState.apiClient) { _, newApiClient in
                if newApiClient != nil && entities.isEmpty { // Only if entities are currently empty
                    fetchEntities()
                }
            }
        }
    }

    private func fetchEntities() {
        guard let client = appState.apiClient else {
            viewError = HAErrors.configurationError("API Client not available. Connect first.")
            // Clear entities if client is lost
            // self.entities = [] // Uncomment if you want to clear data when client is nil
            return
        }

        isLoadingActivities = true
        viewError = nil

        Task {
            do {
                let fetchedStates = try await client.getStates()
                // Sort by friendly name or entity ID for consistent display
                self.entities = fetchedStates.sorted {
                    let name1 = $0.attributes["friendly_name"]?.value as? String ?? $0.entityId
                    let name2 = $1.attributes["friendly_name"]?.value as? String ?? $1.entityId
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }
                print("Fetched and sorted \(fetchedStates.count) entities.")
            } catch {
                print("Error fetching entities: \(error)")
                if let apiError = error as? HomeAssistantAPIClient.APIError {
                    self.viewError = apiError
                } else {
                    self.viewError = HAErrors.unknownError(error.localizedDescription)
                }
                 self.entities = [] // Clear entities on error
            }
            isLoadingActivities = false
        }
    }

    // Helper to format date strings
    private func formattedDate(from dateString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return nil
    }
}

// Preview for LiveActivityListView
struct LiveActivityListView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a dummy AppState and ModelContainer for preview
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: HomeAssistantConnection.self, Item.self, configurations: config)

        let appState = AppState()
        // Simulate a connected state for preview
        let previewConnection = HomeAssistantConnection(
            baseURL: URL(string: "http://preview.home.assistant.io:8123")!,
            accessToken: "fake_token_for_preview",
            instanceName: "Preview HA"
        )
        // Manually insert into context for AppState to load, or set directly for preview
        // container.mainContext.insert(previewConnection) // Not strictly needed if just setting on appState
        // try? container.mainContext.save()

        // To ensure apiClient is initialized in AppState for preview:
        appState.currentConnection = previewConnection // This triggers didSet and initializes apiClient

        // Example entities for preview
        let exampleEntities = [
            HAState(entityId: "light.living_room", state: "on", attributes: ["friendly_name": AnyCodableValue("Living Room Light")], lastChanged: "2023-01-01T10:00:00Z", lastUpdated: "2023-01-01T10:00:00Z"),
            HAState(entityId: "sensor.temperature", state: "22.5", attributes: ["friendly_name": AnyCodableValue("Room Temperature"), "unit_of_measurement": AnyCodableValue("°C")], lastChanged: "2023-01-01T10:05:00Z", lastUpdated: "2023-01-01T10:05:00Z")
        ]

        // Simulate already fetched entities for one preview
        let appStateWithEntities = AppState()
        appStateWithEntities.currentConnection = previewConnection
        // appStateWithEntities.entities = exampleEntities // If entities were directly in AppState

        return Group {
            LiveActivityListView()
                .environment(appState) // apiClient will be there, entities empty initially
                .modelContainer(container)
                .previewDisplayName("Empty, Fetches on Appear")

            // This variant would require LiveActivityListView to accept entities or for AppState to hold them
            // For now, the view manages its own @State entities.
//            LiveActivityListView()
//                .environment(appStateWithData)
//                .modelContainer(container)
//                .onAppear {
//                    // How to inject data into preview for @State var is tricky without changing design
//                }
//                .previewDisplayName("With Preloaded Data (Simulated)")
        }
    }
}
