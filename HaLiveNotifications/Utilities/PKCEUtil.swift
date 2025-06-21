import Foundation
import CryptoKit // For SHA256

struct PKCEUtil {

    /**
     Generates a cryptographically secure random string that can be used as a PKCE code verifier.
     The verifier must be between 43 and 128 characters long and use unreserved characters [A-Z], [a-z], [0-9], '-', '.', '_', '~'.
     */
    static func generateCodeVerifier(length: Int = 128) -> String {
        let allowedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        // Ensure length is within PKCE spec (43-128 characters)
        let validLength = max(43, min(length, 128))

        var randomBytes = [UInt8](repeating: 0, count: validLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, validLength, &randomBytes)

        guard status == errSecSuccess else {
            // Fallback for simulators or environments where SecRandomCopyBytes might fail, though less secure.
            // Or handle error more gracefully. For simplicity, using a less secure fallback for now.
            print("Warning: SecRandomCopyBytes failed. Using a less secure fallback for code_verifier generation.")
            var fallbackString = ""
            for _ in 0..<validLength {
                fallbackString.append(allowedChars.randomElement()!)
            }
            return fallbackString
        }

        return randomBytes.map { byte in
            String(allowedChars[allowedChars.index(allowedChars.startIndex, offsetBy: Int(byte) % allowedChars.count)])
        }.joined()
    }

    /**
     Generates a PKCE code challenge from a code verifier using SHA256 hashing, followed by base64url encoding.
     */
    static func generateCodeChallenge(from codeVerifier: String) -> String? {
        guard let data = codeVerifier.data(using: .utf8) else {
            return nil
        }

        let hashed = SHA256.hash(data: data)

        // Base64url encode the hash
        // Convert digest to Data for base64 encoding
        let hashData = Data(hashed)
        return base64urlEncode(data: hashData)
    }

    /**
     Encodes Data into a base64url string.
     Strips padding (=), replaces + with -, and / with _.
     */
    static func base64urlEncode(data: Data) -> String {
        var base64 = data.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
        base64 = base64.replacingOccurrences(of: "/", with: "_")
        base64 = base64.replacingOccurrences(of: "=", with: "") // Remove padding
        return base64
    }
}
