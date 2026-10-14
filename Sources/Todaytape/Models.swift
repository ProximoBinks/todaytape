import Foundation
import SwiftUI

struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let color: Color
    let notes: String?
    let htmlLink: URL?

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }

    func contains(_ date: Date) -> Bool {
        !isAllDay && start <= date && date < end
    }

    var joinURL: URL? {
        if let htmlLink, Self.isJoinURL(htmlLink) { return htmlLink }
        if let notes, let found = Self.firstJoinURL(in: notes) { return found }
        return htmlLink
    }

    private static let joinHosts = [
        "meet.google.com", "zoom.us", "zoom.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com"
    ]

    static func isJoinURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return joinHosts.contains { host.contains($0) }
    }

    static func firstJoinURL(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.compactMap(\.url).first(where: isJoinURL)
    }
}

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let primary: Bool
}

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date

    var isExpired: Bool {
        expiry.addingTimeInterval(-60) < Date()
    }
}

/// Your own Google OAuth client. Todaytape ships without one: each person
/// creates a Desktop client in their Google Cloud project and adds it here.
struct ClientCredentials: Codable, Equatable {
    var clientID: String
    var clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isUsable: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    /// A short, safe label for the UI: the project number part of the client ID.
    var displayID: String {
        let head = clientID.split(separator: "-").first.map(String.init) ?? clientID
        return head.count > 4 ? "…\(head.suffix(6))" : clientID
    }

    enum ParseError: LocalizedError {
        case notJSON
        case webClient
        case missingFields
        case badClientID

        var errorDescription: String? {
            switch self {
            case .notJSON:
                return "That file isn't a Google client file. Download the JSON from Google Cloud → Clients → your Desktop client."
            case .webClient:
                return "This is a Web application client. Create a Desktop app client instead; Todaytape signs in through your Mac, not a website."
            case .missingFields:
                return "The file has no client ID and secret. Download the JSON again from your Desktop client in Google Cloud."
            case .badClientID:
                return "The client ID should end in .apps.googleusercontent.com."
            }
        }
    }

    /// Accepts the JSON Google offers when you create a client
    /// (`{"installed": {...}}`), or a flat `{"client_id", "client_secret"}`.
    static func parse(_ data: Data) throws -> ClientCredentials {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSON
        }
        if object["web"] != nil, object["installed"] == nil { throw ParseError.webClient }
        let body = (object["installed"] as? [String: Any]) ?? object
        let creds = ClientCredentials(
            clientID: body["client_id"] as? String ?? "",
            clientSecret: body["client_secret"] as? String ?? ""
        )
        guard creds.isUsable else { throw ParseError.missingFields }
        try creds.validate()
        return creds
    }

    func validate() throws {
        guard isUsable else { throw ParseError.missingFields }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw ParseError.badClientID }
    }
}
