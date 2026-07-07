import Foundation
import CryptoKit
import AppKit

class LichessAuthService: ObservableObject {
    static let shared = LichessAuthService()

    @Published var isAuthenticating = false

    private let clientId = "tabia-mac"
    private let redirectURI = "com.ogulcan.tabia://lichess-auth"
    private let authorizeURL = "https://lichess.org/oauth"
    private let tokenURL = "https://lichess.org/api/token"

    private var codeVerifier: String?
    private var completion: ((Result<String, Error>) -> Void)?

    func startOAuth(completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion

        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let url = components.url else {
            completion(.failure(AuthError.invalidURL))
            return
        }

        DispatchQueue.main.async {
            self.isAuthenticating = true
        }
        NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "com.ogulcan.tabia",
              components.host == "lichess-auth" else { return }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            finishAuth(result: .failure(AuthError.denied(error)))
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            finishAuth(result: .failure(AuthError.missingCode))
            return
        }

        exchangeCodeForToken(code: code, verifier: verifier)
    }

    func logout() {
        let token = AppSettings.shared.lichessToken
        guard !token.isEmpty else { return }

        // Revoke the token
        var request = URLRequest(url: URL(string: "https://lichess.org/api/token")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()

        DispatchQueue.main.async {
            AppSettings.shared.lichessToken = ""
        }
    }

    // MARK: - Private

    private func exchangeCodeForToken(code: String, verifier: String) {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientId)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.finishAuth(result: .failure(error))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                self?.finishAuth(result: .failure(AuthError.tokenParseFailed))
                return
            }

            self?.finishAuth(result: .success(accessToken))
        }.resume()
    }

    private func finishAuth(result: Result<String, Error>) {
        DispatchQueue.main.async {
            self.isAuthenticating = false
            self.codeVerifier = nil
            self.completion?(result)
            self.completion = nil
            // Bring the app back to the foreground
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case invalidURL
        case denied(String)
        case missingCode
        case tokenParseFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Failed to build authorization URL"
            case .denied(let reason): return "Authorization denied: \(reason)"
            case .missingCode: return "No authorization code received"
            case .tokenParseFailed: return "Failed to parse token response"
            }
        }
    }
}

// MARK: - Base64-URL encoding (no padding)

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
