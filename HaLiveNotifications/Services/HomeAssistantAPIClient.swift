import Foundation
import SwiftData

// Helper struct for decoding the OAuth token response (used for refresh)
private struct OAuthRefreshTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int // Number of seconds until the access token expires
    // refresh_token might or might not be returned during a refresh operation.
    // If it is, we should update it. Home Assistant typically does not issue a new refresh token
    // when using a refresh token, but good to handle if the spec allows it.
    let refresh_token: String?
    let token_type: String // Should be "Bearer"
}

class HomeAssistantAPIClient {
    // Store the connection object directly to access baseURL, accessToken, and refreshToken
    private var connection: HomeAssistantConnection
    // ModelContext for saving the updated connection (new tokens)
    private let modelContext: ModelContext
    private let urlSession: URLSession

    // To prevent multiple token refresh attempts simultaneously
    private var tokenRefreshTask: Task<String, Error>?

    enum APIError: Error, LocalizedError {
        case invalidURL
        case requestFailed(Error)
        case httpError(statusCode: Int, data: Data?)
        case decodingError(Error)
        case noData
        case tokenRefreshFailed(Error?) // Include underlying error if available
        case noRefreshToken
        case maximumRetriesReached

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The provided URL was invalid."
            case .requestFailed(let error): return "Request failed: \(error.localizedDescription)"
            case .httpError(let statusCode, _): return "HTTP Error: Status Code \(statusCode)"
            case .decodingError(let error): return "Failed to decode response: \(error.localizedDescription)"
            case .noData: return "No data received from server."
            case .tokenRefreshFailed(let underlyingError):
                if let underlyingError = underlyingError {
                    return "Failed to refresh the access token: \(underlyingError.localizedDescription)"
                }
                return "Failed to refresh the access token."
            case .noRefreshToken: return "No refresh token available to refresh the access token."
            case .maximumRetriesReached: return "Maximum token refresh retries reached."
            }
        }
    }

    init(connection: HomeAssistantConnection, modelContext: ModelContext, urlSession: URLSession = .shared) {
        self.connection = connection
        self.modelContext = modelContext
        self.urlSession = urlSession
    }

    // Safely get the current access token, waiting for an ongoing refresh if necessary
    private func getCurrentAccessToken() async throws -> String {
        if let refreshTask = tokenRefreshTask {
            // If a refresh task is already in progress, await its result
            return try await refreshTask.value
        }
        // Otherwise, return the current access token from the connection
        return connection.accessToken
    }


    // MARK: - Generic Request Performer
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        expectedStatusCode: Int = 200, // Or a range for success
        isRetry: Bool = false // To prevent infinite retry loops
    ) async throws -> T {
        // Ensure the base URL is valid for constructing the full URL
        guard let url = URL(string: endpoint, relativeTo: connection.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Get the access token, potentially waiting for an ongoing refresh
        let currentToken = try await getCurrentAccessToken()
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(URLError(.badServerResponse))
        }

        // Check for 401 Unauthorized and if this is not already a retry attempt
        if httpResponse.statusCode == 401 && !isRetry {
            print("Received 401 Unauthorized. Attempting token refresh.")
            do {
                _ = try await refreshToken() // Perform refresh, this updates connection.accessToken
                print("Token refreshed successfully. Retrying original request.")
                // Retry the request once with the new token
                return try await performRequest(endpoint: endpoint, method: method, body: body, expectedStatusCode: expectedStatusCode, isRetry: true)
            } catch {
                print("Token refresh failed: \(error.localizedDescription)")
                // If refresh fails, throw the specific refresh error or the original 401
                throw error // This will be one of the APIError.tokenRefreshFailed or .noRefreshToken
            }
        }

        guard httpResponse.statusCode == expectedStatusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        // Handle cases where T is Void or an empty struct for responses with no body
        if T.self == Void.self || (data.isEmpty && String(describing: T.self).contains("EmptyResponse")) {
            if data.isEmpty {
                // Attempt to decode an empty JSON object if T can be represented by it
                return try JSONDecoder().decode(T.self, from: "{}".data(using: .utf8)!)
            }
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Token Refresh
    @MainActor // Ensure model context operations are on the main actor
    private func refreshToken() async throws -> String {
        // If a refresh task is already in progress, return its existing Task to await.
        if let existingTask = tokenRefreshTask {
            return try await existingTask.value
        }

        // Create a new Task for token refresh.
        let newRefreshTask = Task<String, Error> {
            guard let currentRefreshToken = connection.refreshToken, !currentRefreshToken.isEmpty else {
                throw APIError.noRefreshToken
            }

            // The token endpoint is on the Home Assistant instance itself
            guard let tokenURL = URL(string: "/oauth2/token", relativeTo: connection.baseURL) else {
                throw APIError.invalidURL
            }

            print("Attempting to refresh token with URL: \(tokenURL.absoluteString)")

            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let bodyParameters = [
                "grant_type": "refresh_token",
                "refresh_token": currentRefreshToken,
                "client_id": Constants.homeAssistantOAuthClientID // Client ID is required for refresh
            ]
            request.httpBody = bodyParameters
                .map { key, value in "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
                .joined(separator: "&")
                .data(using: .utf8)

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    print("Token refresh HTTP error: \( (response as? HTTPURLResponse)?.statusCode ?? 0). Body: \(errorBody)")
                    throw APIError.tokenRefreshFailed(nil) // Consider parsing error response from HA if available
                }

                let tokenResponse = try JSONDecoder().decode(OAuthRefreshTokenResponse.self, from: data)

                // Update the connection model with the new tokens
                self.connection.accessToken = tokenResponse.access_token
                if let newRefreshToken = tokenResponse.refresh_token, !newRefreshToken.isEmpty {
                    // Home Assistant typically does not issue a new refresh token during a refresh_token grant.
                    // However, if it does, we should store it.
                    self.connection.refreshToken = newRefreshToken
                    print("Refresh token was also updated by the server.")
                }
                self.connection.lastConnectedAt = Date() // Update last used timestamp

                try modelContext.save() // Persist changes to SwiftData
                print("Successfully saved new tokens to HomeAssistantConnection.")

                self.tokenRefreshTask = nil // Clear the task reference once completed successfully.
                return tokenResponse.access_token
            } catch {
                self.tokenRefreshTask = nil // Clear the task reference on failure.
                if error is APIError { throw error } // Re-throw our specific API errors
                throw APIError.tokenRefreshFailed(error) // Wrap other errors
            }
        }

        self.tokenRefreshTask = newRefreshTask
        return try await newRefreshTask.value
    }


    // MARK: - API Endpoints

    /// Checks the API status.
    /// Corresponds to GET /api/
    func checkAPIStatus() async throws -> APIStatusResponse {
        return try await performRequest(endpoint: "api/")
    }

    /// Fetches all states from Home Assistant.
    /// Corresponds to GET /api/states
    func getStates() async throws -> [HAState] {
        return try await performRequest(endpoint: "api/states")
    }

    /// Fetches a specific state from Home Assistant.
    /// Corresponds to GET /api/states/<entity_id>
    func getState(entityId: String) async throws -> HAState {
        return try await performRequest(endpoint: "api/states/\(entityId)")
    }

    /// Calls a service in Home Assistant.
    /// Corresponds to POST /api/services/<domain>/<service>
    func callService(domain: String, service: String, serviceData: [String: Any]? = nil) async throws -> [HAState] { // Service calls often return the states that changed
        let endpoint = "api/services/\(domain)/\(service)"
        var bodyData: Data? = nil
        if let serviceData = serviceData {
            // Convert [String: Any] to Data.
            // Ensure AnyCodableValue or similar is used if serviceData contains mixed types.
            // For simplicity, assuming serviceData is JSON serializable directly.
            // A more robust solution uses a proper Codable struct for serviceData.
            bodyData = try? JSONSerialization.data(withJSONObject: serviceData, options: [])
        }
        // Service calls usually return 200 OK with a body (often new states) or an empty array.
        return try await performRequest(endpoint: endpoint, method: "POST", body: bodyData, expectedStatusCode: 200)
    }

    // Add more methods here:
    // func getServices() async throws -> [HAService] { ... }
    // func getConfig() async throws -> HAConfig { ... }
}

// Example of an EmptyResponse struct if needed for POST calls that return nothing.
struct EmptyResponse: Decodable {}
