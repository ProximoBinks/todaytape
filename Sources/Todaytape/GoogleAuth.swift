import AppKit
import CryptoKit
import Foundation
import Network

/// Errors written for the person setting Todaytape up, with the fix in the message.
enum AuthError: LocalizedError, Equatable {
    case missingCredentials
    case listenerFailed
    case cancelled
    case timedOut
    case accessDenied
    case invalidClient
    case calendarAPIDisabled
    case sessionExpired
    case google(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add your Google client first (step 2)."
        case .listenerFailed:
            return "Couldn't open a local port for Google's sign-in. Try again."
        case .cancelled:
            return "Sign-in was cancelled."
        case .timedOut:
            return "Sign-in timed out. Click Connect to try again."
        case .accessDenied:
            return "Google didn't grant access. If you saw \"Access blocked\", add your Gmail as a test user under Audience in Google Cloud, then connect again."
        case .invalidClient:
            return "Google rejected the client ID or secret. Check they come from a Desktop app client, or import its JSON again."
        case .calendarAPIDisabled:
            return "The Google Calendar API is off for your project. Enable it (step 1), wait a minute, then click Refresh."
        case .sessionExpired:
            return "Your Google sign-in expired. Click Connect to sign in again. While your app is in Testing, Google ends sign-ins after 7 days."
        case .google(let message):
            return message
        case .http(let code, _):
            return "Google returned an error (HTTP \(code)). Click Refresh to try again."
        }
    }

    /// Map a Google error body to something actionable.
    static func from(status: Int, body: String) -> AuthError {
        let lower = body.lowercased()
        if lower.contains("invalid_grant") { return .sessionExpired }
        if lower.contains("invalid_client") || lower.contains("unauthorized_client") { return .invalidClient }
        if lower.contains("accessnotconfigured") || lower.contains("service_disabled")
            || lower.contains("has not been used in project") {
            return .calendarAPIDisabled
        }
        if status == 401 { return .sessionExpired }
        return .http(status, body)
    }
}

enum GoogleAuth {
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    static let timeout: TimeInterval = 5 * 60

    /// Opens Google's consent page in the browser and waits for the redirect
    /// to a one-off server on 127.0.0.1 (the Desktop app loopback flow, with PKCE).
    static func signIn(clientID: String, clientSecret: String, server: LoopbackServer = LoopbackServer()) async throws -> OAuthTokens {
        let verifier = randomURLSafe(bytes: 32)
        let state = randomURLSafe(bytes: 16)
        let port = try await server.start(expectedState: state)
        let redirect = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkceChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = comps.url else { throw AuthError.listenerFailed }

        let timer = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            server.cancel(with: .timedOut)
        }
        defer { timer.cancel() }

        async let codeTask = server.waitForCode()
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }
        let code = try await codeTask
        return try await exchange(
            clientID: clientID,
            clientSecret: clientSecret,
            code: code,
            redirect: redirect,
            verifier: verifier
        )
    }

    static func refresh(clientID: String, clientSecret: String, refreshToken: String) async throws -> OAuthTokens {
        let body = form([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        let json = try await postToken(body: body)
        return try tokens(from: json, fallbackRefresh: refreshToken)
    }

    /// Best effort: tell Google to forget the grant when you disconnect.
    static func revoke(_ token: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func exchange(
        clientID: String,
        clientSecret: String,
        code: String,
        redirect: String,
        verifier: String
    ) async throws -> OAuthTokens {
        let body = form([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect
        ])
        let json = try await postToken(body: body)
        return try tokens(from: json, fallbackRefresh: nil)
    }

    private static func postToken(body: Data) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AuthError.from(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.google("Google's token reply wasn't JSON. Try again.")
        }
        return json
    }

    private static func tokens(from json: [String: Any], fallbackRefresh: String?) throws -> OAuthTokens {
        guard let access = json["access_token"] as? String else {
            throw AuthError.google("Google's reply had no access token. Try again.")
        }
        let expires = json["expires_in"] as? Int ?? 3600
        let refresh = (json["refresh_token"] as? String) ?? fallbackRefresh
        return OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiry: Date().addingTimeInterval(TimeInterval(expires))
        )
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    private static func pkceChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A one-request HTTP server on 127.0.0.1 that catches Google's redirect.
/// Requests without a matching `state` (favicon fetches, browser preconnects,
/// other pages) get a 404 and are ignored rather than ending the sign-in.
final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "todaytape.loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var pending: Result<String, Error>?
    private var expectedState = ""
    private var finished = false

    func start(expectedState: String) async throws -> UInt16 {
        self.expectedState = expectedState
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        guard let port = listener.port?.rawValue else { throw AuthError.listenerFailed }
        return port
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let pending = self.pending {
                    self.pending = nil
                    cont.resume(with: pending)
                } else {
                    self.continuation = cont
                }
            }
        }
    }

    func cancel(with error: AuthError = .cancelled) {
        queue.async { self.finish(.failure(error)) }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let first = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let path = first.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
            let value = { (name: String) in items.first(where: { $0.name == name })?.value }

            let status: String
            let message: String
            if value("state") != self.expectedState || self.finished {
                status = "404 Not Found"
                message = "Nothing here."
            } else if let err = value("error") {
                status = "200 OK"
                message = "Google didn't grant access (\(Self.escape(err))). You can close this tab and check the Todaytape window."
                self.finish(.failure(err == "access_denied" ? AuthError.accessDenied : AuthError.google("Google said: \(err)")))
            } else if let code = value("code"), !code.isEmpty {
                status = "200 OK"
                message = "Todaytape is connected to Google Calendar. You can close this tab."
                self.finish(.success(code))
            } else {
                status = "404 Not Found"
                message = "Nothing here."
            }
            let body = """
            <!doctype html><meta charset="utf-8"><title>Todaytape</title>
            <body style="font:16px -apple-system,system-ui,sans-serif;padding:3rem;max-width:32rem;color:#16161a">
            <p style="font-size:20px;font-weight:600;margin:0 0 .5rem">Todaytape</p><p>\(message)</p></body>
            """
            let response = Data("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Runs on `queue`.
    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        listener?.cancel()
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            pending = result
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
