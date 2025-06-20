import Foundation

class HomeAssistantAPIClient {
    private let baseURL: URL
    private let accessToken: String
    private let urlSession: URLSession

    enum APIError: Error, LocalizedError {
        case invalidURL
        case requestFailed(Error)
        case httpError(statusCode: Int, data: Data?)
        case decodingError(Error)
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The provided URL was invalid."
            case .requestFailed(let error): return "Request failed: \(error.localizedDescription)"
            case .httpError(let statusCode, _): return "HTTP Error: Status Code \(statusCode)"
            case .decodingError(let error): return "Failed to decode response: \(error.localizedDescription)"
            case .noData: return "No data received from server."
            }
        }
    }

    init(connection: HomeAssistantConnection, urlSession: URLSession = .shared) {
        self.baseURL = connection.baseURL
        self.accessToken = connection.accessToken
        self.urlSession = urlSession
    }

    // MARK: - Generic Request Performer
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        expectedStatusCode: Int = 200 // Or a range for success
    ) async throws -> T {
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(URLError(.badServerResponse)) // Or a custom error
        }

        guard httpResponse.statusCode == expectedStatusCode else {
            // Log detailed error if possible
            // print("HTTP Error \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "No body")")
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        // Some Home Assistant API (like POST for services) might return 200 or 201 with no body or an empty array.
        // Handle cases where T is `Void` or an empty struct for such scenarios.
        if T.self == Void.self || (data.isEmpty && String(describing: T.self).contains("EmptyResponse")) {
             // If expecting no content and got no content, return as success.
             // This requires a way to signify `Void` or a specific "empty" type.
             // For now, we assume successful status code means success, and decoding handles empty if T is appropriate.
             // If data is empty and T is not Optional or specifically designed for empty, decode will fail.
             // A common pattern is to have an `EmptyResponse: Decodable` struct.
            if data.isEmpty {
                // If T can be represented by "empty" (e.g. an empty struct), this might work.
                // This is a simplification. Robust handling might need type checks.
                return try JSONDecoder().decode(T.self, from: "{}".data(using: .utf8)!) // Or handle based on T
            }
        }


        do {
            let decoder = JSONDecoder()
            // Add custom date decoding strategy if HA returns non-standard dates not covered by ISO8601.
            // decoder.dateDecodingStrategy = .iso8601 // Default for many cases
            return try decoder.decode(T.self, from: data)
        } catch {
            // print("Decoding error: \(error). Data: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw APIError.decodingError(error)
        }
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
