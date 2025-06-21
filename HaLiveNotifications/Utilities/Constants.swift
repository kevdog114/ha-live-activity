//
//  Constants.swift
//  HaLiveNotifications
//
//  Created by Kevin Schaefer on 6/20/25.
//

import Foundation

struct Constants {
    // MARK: - My Home Assistant OAuth Configuration
    // These URLs are for the production instance of my.home-assistant.io
    static let myHomeAssistantBaseURL = "https://my.home-assistant.io"
    // Corrected URL for initiating OAuth via My Home Assistant
    static let myHomeAssistantRedirectOAuthURL = "\(myHomeAssistantBaseURL)/redirect/oauth"
    // The token URL is not on my.home-assistant.io, but on the user's HA instance.
    // Example: "http://[YOUR_INSTANCE_URL]/oauth2/token"
    // This will be constructed dynamically in the app.

    // MARK: - OAuth Client Configuration
    // Replace with your actual client ID from Home Assistant registration
    static let homeAssistantOAuthClientID = "YOUR_CLIENT_ID"
    // This should be a unique URL scheme for your app, e.g., "halivenotifications://"
    // Ensure this is configured in Info.plist
    static let homeAssistantOAuthRedirectURIScheme = "halivenotifications"
    static let homeAssistantOAuthRedirectURI = "\(homeAssistantOAuthRedirectURIScheme)://auth"


    // MARK: - General Home Assistant
    static let homeAssistantDefaultPort = 8123
    static let homeAssistantWebSocketPath = "/api/websocket"
    static let homeAssistantAPIPath = "/api/"

    // MARK: - User Defaults Keys
    // Add any keys for UserDefaults if needed

    // MARK: - App Specific
    // Add any other app-specific constants
}

// Note: The actual token exchange typically happens with the Home Assistant instance URL itself,
// not my.home-assistant.io. 'my.home-assistant.io' helps redirect to the correct instance.
// The authorization call might look like:
// https://my.home-assistant.io/redirect/oauth?client_id=YOUR_CLIENT_ID&redirect_uri=YOUR_REDIRECT_URI&response_type=code&scope=read:entities+write:services
// This will then redirect to http://[YOUR_INSTANCE_URL]/oauth2/authorize?...
// After user authorization, the instance redirects back to YOUR_REDIRECT_URI with the code.
// Then, your app exchanges the code for a token directly with http://[YOUR_INSTANCE_URL]/oauth2/token.
// So, myHomeAssistantTokenURL above is likely incorrect for direct use. The token URL will be dynamic based on the user's HA instance.
