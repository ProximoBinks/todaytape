import Foundation
import SwiftUI

enum CalendarAPI {
    static func validToken(credentials: ClientCredentials, tokens: inout OAuthTokens, force: Bool = false) async throws -> String {
        if !force && !tokens.isExpired { return tokens.accessToken }
        guard let refresh = tokens.refreshToken else {
            throw AuthError.sessionExpired
        }
        tokens = try await GoogleAuth.refresh(
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret,
            refreshToken: refresh
        )
        try Config.saveTokens(tokens)
        return tokens.accessToken
    }

    static func calendarList(token: String) async throws -> [CalendarInfo] {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader")!
        let json = try await get(url, token: token)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let title = (item["summary"] as? String) ?? id
            let hex = (item["backgroundColor"] as? String) ?? "#4285F4"
            let primary = item["primary"] as? Bool ?? false
            return CalendarInfo(id: id, title: title, color: Color(hex: hex), primary: primary)
        }
    }

    static func events(
        token: String,
        calendar: CalendarInfo,
        start: Date,
        end: Date
    ) async throws -> [DayEvent] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let encodedID = calendar.id.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendar.id
        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        comps.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "maxResults", value: "80")
        ]
        guard let url = comps.url else { return [] }
        let json = try await get(url, token: token)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            parseEvent(item, calendar: calendar)
        }
    }

    private static func parseEvent(_ item: [String: Any], calendar: CalendarInfo) -> DayEvent? {
        guard let id = item["id"] as? String else { return nil }
        let title = (item["summary"] as? String) ?? "(No title)"
        let startBlock = item["start"] as? [String: Any] ?? [:]
        let endBlock = item["end"] as? [String: Any] ?? [:]
        let allDay: Bool
        let start: Date
        let end: Date
        if let day = startBlock["date"] as? String, let s = parseDateOnly(day) {
            allDay = true
            start = s
            end = (endBlock["date"] as? String).flatMap(parseDateOnly) ?? s.addingTimeInterval(86400)
        } else if let dt = startBlock["dateTime"] as? String, let s = parseDateTime(dt) {
            allDay = false
            start = s
            end = (endBlock["dateTime"] as? String).flatMap(parseDateTime) ?? s.addingTimeInterval(1800)
        } else {
            return nil
        }
        let notes = item["description"] as? String
        let link = (item["htmlLink"] as? String).flatMap(URL.init(string:))
        let loc = item["location"] as? String
        let hangout = (item["hangoutLink"] as? String).flatMap(URL.init(string:))
        let joinedNotes = [notes, loc].compactMap { $0 }.joined(separator: "\n")
        return DayEvent(
            id: "\(calendar.id)|\(id)",
            title: title,
            start: start,
            end: end,
            isAllDay: allDay,
            calendarID: calendar.id,
            calendarTitle: calendar.title,
            color: calendar.color,
            notes: joinedNotes.isEmpty ? nil : joinedNotes,
            htmlLink: hangout ?? link
        )
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func parseDateOnly(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    private static func get(_ url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AuthError.from(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.google("Google Calendar's reply wasn't JSON. Click Refresh to try again.")
        }
        return json
    }
}
