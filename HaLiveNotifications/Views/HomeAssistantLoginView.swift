import SwiftUI
import SwiftData

// FIX: The section has been extracted into its own View struct.
// This makes the dependency explicit and is a more robust pattern.
private struct DiscoveredInstancesSectionView: View {
    // It receives the service as a direct parameter, not from the environment.
    var discoveryService: HomeAssistantDiscoveryService
    
    // It also needs bindings to the parent view's state that it can modify.
    @Binding var selectedDiscoveredInstance: DiscoveredInstance?
    @Binding var manualURLString: String
    @Binding var showManualSetup: Bool

    var body: some View {
        Section(header: Text("Discovered Instances").font(.headline)) {
            List(discoveryService.discoveredInstances) { instance in
                Button(action: {
                    print("Selected instance " + (instance.host))
                    self.selectedDiscoveredInstance = instance
                    self.manualURLString = instance.baseURL?.absoluteString ?? ""
                    withAnimation {
                        self.showManualSetup = true
                    }
                }) {
                    VStack(alignment: .leading) {
                        Text(instance.name)
                            .fontWeight(.bold)
                        if let url = instance.baseURL {
                            Text(url.absoluteString)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }
}

struct HomeAssistantLoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var manualURLString: String = ""
    @State private var accessToken: String = ""
    @State private var showManualSetup: Bool = false
    @State private var discoveryService = HomeAssistantDiscoveryService()
    @State private var selectedDiscoveredInstance: DiscoveredInstance?

    @State private var connectingToInstanceName: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if appState.isLoading {
                    if let instanceName = connectingToInstanceName {
                        ProgressView("Connecting to \(instanceName)...")
                    } else {
                        ProgressView("Processing...")
                    }
                } else {
                    if let error = appState.connectionError {
                        ErrorDisplayView(error: error)
                            .padding(.bottom)
                    }

                    // FIX: We now create the new view struct and explicitly pass it the data it needs.
                    if !discoveryService.discoveredInstances.isEmpty && !showManualSetup {
                        DiscoveredInstancesSectionView(
                            discoveryService: discoveryService,
                            selectedDiscoveredInstance: $selectedDiscoveredInstance,
                            manualURLString: $manualURLString,
                            showManualSetup: $showManualSetup
                        )
                    }

                    manualSetupToggle

                    if showManualSetup {
                        manualSetupSection
                    }
                }
            }
            .navigationTitle("Connect to Home Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.connectionError = nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                appState.connectionError = nil
                if discoveryService.discoveredInstances.isEmpty {
                    discoveryService.startDiscovery()
                }
            }
            .onChange(of: appState.currentConnection) { _, newValue in
                if newValue != nil {
                    dismiss()
                }
            }
        }
    }

    private var manualSetupToggle: some View {
        Button(action: {
            withAnimation {
                showManualSetup.toggle()
                if !showManualSetup {
                    manualURLString = ""
                    accessToken = ""
                    selectedDiscoveredInstance = nil
                    appState.connectionError = nil
                }
            }
        }) {
            Text(showManualSetup ? "Hide Manual Setup" : (discoveryService.discoveredInstances.isEmpty ? "Manual Setup" : "Or Enter Manually..."))
                .padding(.vertical, 5)
        }
    }

    private var manualSetupSection: some View {
        VStack(alignment: .leading) {
            // Force-unwrapping here can be risky if `selectedDiscoveredInstance` is nil.
            // Let's use a safer default.
            Text(selectedDiscoveredInstance != nil ? "Enter Token for \(selectedDiscoveredInstance!.name)" : "Manual Configuration")
                .font(.headline)
                .padding(.bottom, 5)

            TextField("Home Assistant URL", text: $manualURLString, prompt: Text("e.g., http://homeassistant.local:8123"))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .disabled(selectedDiscoveredInstance != nil)

            SecureField("Long-Lived Access Token", text: $accessToken)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            HStack {
                Spacer()
                Button("Connect", action: handleConnect)
                    .padding()
                    .buttonStyle(.borderedProminent)
                    .disabled(manualURLString.isEmpty || accessToken.isEmpty || appState.isLoading)
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private func handleConnect() {
        appState.connectionError = nil
        guard !accessToken.isEmpty else {
            appState.connectionError = HAErrors.authenticationError("Access token cannot be empty.")
            return
        }
        
        guard let url = URL(string: manualURLString) else {
            appState.connectionError = HAErrors.configurationError("Invalid URL format.")
            return
        }

        let nameToConnect = selectedDiscoveredInstance?.name ?? url.host ?? "Manual Instance"
        connectingToInstanceName = nameToConnect

        let newConnection = HomeAssistantConnection(baseURL: url, accessToken: accessToken, instanceName: nameToConnect)
        Task {
            await appState.saveConnection(connection: newConnection, context: modelContext)
            connectingToInstanceName = nil
        }
    }
}

struct HomeAssistantLoginView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: HomeAssistantConnection.self, configurations: config)
        let appState = AppState()

        return HomeAssistantLoginView()
            .environment(appState)
            .modelContainer(container)
    }
}
