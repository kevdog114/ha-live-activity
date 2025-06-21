import SwiftUI
import SwiftData

struct HomeAssistantLoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // For opening the OAuth URL in the browser
    @Environment(\.openURL) private var openURL

    // State to manage the Home Assistant instance URL if needed post-OAuth or for manual input
    @State private var instanceURLString: String = ""
    // State to hold the authorization code received from the callback
    @State private var authorizationCode: String? = nil
    // State to indicate if we are currently in the process of exchanging the code for a token
    @State private var isExchangingCode: Bool = false

    // Temporary state for instance name during connection
    @State private var connectingToInstanceName: String? = nil

    // PKCE and state parameters are now managed in AppState


    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if appState.isLoading || isExchangingCode {
                    ProgressView(isExchangingCode ? "Authenticating..." : (connectingToInstanceName != nil ? "Connecting to \(connectingToInstanceName!)..." : "Processing..."))
                } else {
                    if let error = appState.connectionError {
                        ErrorDisplayView(error: error)
                            .padding(.bottom)
                    }

                    Text("Connect your Home Assistant instance using the official OAuth2 method.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: startOAuthFlow) {
                        Text("Login with HomeAssistant")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // Optional: Allow manual input of HA URL if my.home-assistant.io cannot determine it
                    // or if the user is not using Home Assistant Cloud.
                    // This might be better placed after the initial OAuth redirect if the instance URL isn't found.
                    Section(header: Text("Or Enter Instance URL Manually").font(.caption)) {
                        TextField("Home Assistant URL (if needed)", text: $instanceURLString, prompt: Text("e.g., http://homeassistant.local:8123"))
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
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
                // Reset state if view appears
                authorizationCode = nil
                isExchangingCode = false
                // If no auth code is present (i.e., we are not returning from a successful redirect)
                // and not currently exchanging a code, it's safe to clear any pending OAuth data in AppState.
                // This handles cases where the user navigates away and back to the login view
                // before completing an OAuth flow.
                if authorizationCode == nil && !isExchangingCode {
                    appState.clearPendingOAuthData()
                }
            }
            .onOpenURL { url in
                // This will be called when the app is opened via its custom URL scheme
                handleOAuthCallback(url: url)
            }
            .onChange(of: appState.currentConnection) { _, newValue in
                if newValue != nil {
                    dismiss() // Dismiss if connection is successful
                }
            }
        }
    }

    private func startOAuthFlow() {
        appState.connectionError = nil

        // 1. Generate and store state in AppState
        let generatedState = PKCEUtil.generateCodeVerifier(length: 32) // state can be shorter
        appState.pendingOAuthState = generatedState
        print("Generated state and stored in AppState: \(generatedState)")

        // 2. Generate and store code_verifier in AppState, create code_challenge
        let generatedCodeVerifier = PKCEUtil.generateCodeVerifier()
        guard let codeChallenge = PKCEUtil.generateCodeChallenge(from: generatedCodeVerifier) else {
            appState.connectionError = HAErrors.configurationError("Could not generate PKCE code challenge.")
            appState.clearPendingOAuthData() // Clear any partial state
            return
        }
        appState.pendingPkceCodeVerifier = generatedCodeVerifier
        // print("Generated PKCE Verifier and stored in AppState: \(generatedCodeVerifier)") // For debugging
        print("Generated PKCE Challenge: \(codeChallenge)")

        var components = URLComponents(string: Constants.myHomeAssistantRedirectOAuthURL)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Constants.homeAssistantOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: Constants.homeAssistantOAuthRedirectURI),
            URLQueryItem(name: "state", value: generatedState),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
            // Add any scopes if necessary, e.g.,
            // URLQueryItem(name: "scope", value: "read:entities write:services")
        ]

        guard let authURL = components?.url else {
            appState.connectionError = HAErrors.configurationError("Could not create authorization URL.")
            appState.clearPendingOAuthData() // Clear stored state/verifier on error
            return
        }

        print("Redirecting to OAuth URL: \(authURL.absoluteString)")
        openURL(authURL)
    }

    private func handleOAuthCallback(url: URL) {
        print("Received callback URL: \(url.absoluteString)")
        guard url.scheme == Constants.homeAssistantOAuthRedirectURIScheme else {
            print("Callback URL scheme does not match.")
            appState.clearPendingOAuthData()
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Validate state
        guard let receivedState = components?.queryItems?.first(where: { $0.name == "state" })?.value else {
            appState.connectionError = HAErrors.authenticationError("OAuth callback missing 'state' parameter.")
            appState.clearPendingOAuthData()
            return
        }

        guard let storedState = appState.pendingOAuthState, receivedState == storedState else {
            appState.connectionError = HAErrors.authenticationError("OAuth 'state' parameter mismatch. Possible CSRF attack.")
            appState.clearPendingOAuthData()
            return
        }

        // State is valid, proceed to get code
        if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
            self.authorizationCode = code
            if let haInstanceURL = components?.queryItems?.first(where: { $0.name == "instance_url"})?.value {
                self.instanceURLString = haInstanceURL
                print("HA Instance URL from callback: \(haInstanceURL)")
            }
            // PKCE verifier and state are still in AppState, to be used in exchangeCodeForToken
            // and cleared afterwards.
            exchangeCodeForToken(code: code)
        } else if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            let errorDescription = components?.queryItems?.first(where: { $0.name == "error_description" })?.value ?? "Unknown OAuth error."
            appState.connectionError = HAErrors.authenticationError("OAuth Error: \(error) - \(errorDescription)")
            appState.clearPendingOAuthData() // Clear state on error
            isExchangingCode = false
        }
    }

    private func exchangeCodeForToken(code: String) {
        guard !instanceURLString.isEmpty, let haInstanceBaseURL = URL(string: instanceURLString) else {
            appState.connectionError = HAErrors.configurationError("Home Assistant instance URL is not set or invalid. Please enter it manually.")
            appState.clearPendingOAuthData()
            isExchangingCode = false
            return
        }

        guard let currentPkceCodeVerifier = appState.pendingPkceCodeVerifier else {
            appState.connectionError = HAErrors.authenticationError("PKCE code verifier missing from AppState. Cannot exchange token.")
            appState.clearPendingOAuthData()
            isExchangingCode = false
            return
        }

        guard let tokenURL = URL(string: "/oauth2/token", relativeTo: haInstanceBaseURL) else {
            appState.connectionError = HAErrors.configurationError("Could not create token exchange URL.")
            appState.clearPendingOAuthData()
            isExchangingCode = false
            return
        }

        isExchangingCode = true
        appState.connectionError = nil

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Constants.homeAssistantOAuthRedirectURI,
            "client_id": Constants.homeAssistantOAuthClientID,
            "code_verifier": currentPkceCodeVerifier // Add PKCE code_verifier
        ]

        // Ensure percent encoding is applied to each key and value if necessary,
        // though for these specific values, it's usually not an issue.
        // URLComponents.queryItems handles this better if building the body string this way.
        // For x-www-form-urlencoded, percent encoding is important.
        let bodyString = bodyParameters
            .map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    print("Token exchange HTTP error: \( (response as? HTTPURLResponse)?.statusCode ?? 0). Body: \(errorBody)")
                    throw HAErrors.authenticationError("Failed to exchange token. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0). \(errorBody)")
                }

                let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

                let instanceName = haInstanceBaseURL.host ?? "Home Assistant"
                connectingToInstanceName = instanceName

                let newConnection = HomeAssistantConnection(
                    baseURL: haInstanceBaseURL,
                    accessToken: tokenResponse.access_token,
                    refreshToken: tokenResponse.refresh_token,
                    instanceName: instanceName
                )
                await appState.saveConnection(connection: newConnection, context: modelContext)

            } catch {
                appState.connectionError = HAErrors.authenticationError("Token exchange failed: \(error.localizedDescription)")
            }
            isExchangingCode = false
            connectingToInstanceName = nil
            appState.clearPendingOAuthData() // Clear PKCE and state values from AppState after completion
        }
    }
}

// Helper struct for decoding the token response
private struct OAuthTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let token_type: String
    let expires_in: Int
}


struct HomeAssistantLoginView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: HomeAssistantConnection.self, configurations: config)
        let appState = AppState()

        // Create a dummy HomeAssistantConnection for preview if needed
        // let exampleConnection = HomeAssistantConnection(baseURL: URL(string: "http://example.com")!, accessToken: "dummy_token")
        // container.mainContext.insert(exampleConnection)
        // appState.currentConnection = exampleConnection // To simulate logged in state for other views

        return HomeAssistantLoginView()
            .environment(appState)
            .modelContainer(container)
    }
}
