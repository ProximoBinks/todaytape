import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Where setup stands. Drives the tape, the menu and the Settings window.
    enum Phase: Equatable {
        case needsClient      // no Google client yet
        case needsSignIn      // client saved, not connected
        case connecting       // browser open, waiting for Google
        case connected
    }

    @Published var settings: AppSettings
    @Published var events: [DayEvent] = []
    @Published var calendars: [CalendarInfo] = []
    @Published private(set) var credentials: ClientCredentials?
    @Published private(set) var phase: Phase = .needsClient
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var openAtLogin = false
    @Published var expanded: Bool = false
    @Published var overlayHidden: Bool = false

    var signedIn: Bool { phase == .connected }

    private var tokens: OAuthTokens?
    private var poll: Timer?
    private var signInServer: LoopbackServer?

    init() {
        Config.migrateLegacyFolderIfNeeded()
        settings = Config.loadSettings()
        credentials = Config.loadCredentials()

        // Early builds stored the client in settings.json. Move it to credentials.json once.
        if settings.hasLegacyCredentials {
            if credentials == nil, let legacy = settings.legacyCredentials, (try? Config.saveCredentials(legacy)) != nil {
                credentials = legacy
            }
            settings.dropLegacyCredentials()
            Config.saveSettings(settings)
        }

        tokens = Config.loadTokens()
        openAtLogin = LoginItem.isEnabled
        expanded = settings.expanded
        overlayHidden = settings.overlayHidden
        phase = Self.phase(credentials: credentials, tokens: tokens)
    }

    private static func phase(credentials: ClientCredentials?, tokens: OAuthTokens?) -> Phase {
        guard credentials?.isUsable == true else { return .needsClient }
        return tokens == nil ? .needsSignIn : .connected
    }

    // MARK: Lifecycle

    func start() {
        poll?.invalidate()
        AppClock.shared.start()
        poll = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
        poll?.tolerance = 30
        Task { await reload() }
        if phase != .connected {
            OverlayController.shared.openSettings()
        }
    }

    // MARK: Setup

    /// Save a client from Google's downloaded JSON.
    func importClient(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try saveClient(try ClientCredentials.parse(data))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Save a client typed or pasted into Settings.
    func saveClient(id: String, secret: String) {
        do {
            try saveClient(ClientCredentials(clientID: id, clientSecret: secret))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func saveClient(_ creds: ClientCredentials) throws {
        try creds.validate()
        let changed = creds != credentials
        try Config.saveCredentials(creds)
        credentials = creds
        lastError = nil
        if changed {
            // Tokens belong to the old client; they won't refresh under a new one.
            clearSession()
        }
        phase = Self.phase(credentials: credentials, tokens: tokens)
    }

    /// Forget the client, the sign-in and the calendar list. Colours and appearance stay.
    func removeClient() {
        Task { await disconnect() }
        Config.clearCredentials()
        credentials = nil
        phase = .needsClient
    }

    func connect() async {
        guard let creds = credentials, creds.isUsable else {
            lastError = AuthError.missingCredentials.localizedDescription
            phase = .needsClient
            return
        }
        lastError = nil
        phase = .connecting
        let server = LoopbackServer()
        signInServer = server
        do {
            let fresh = try await GoogleAuth.signIn(clientID: creds.clientID, clientSecret: creds.clientSecret, server: server)
            guard signInServer === server else { return }
            signInServer = nil
            tokens = fresh
            try Config.saveTokens(fresh)
            phase = .connected
            OverlayController.shared.apply(animated: false)
            await reload()
        } catch {
            guard signInServer === server else { return }
            signInServer = nil
            phase = Self.phase(credentials: credentials, tokens: tokens)
            if (error as? AuthError) != .cancelled {
                lastError = error.localizedDescription
            }
        }
    }

    func cancelConnect() {
        signInServer?.cancel(with: .cancelled)
    }

    func disconnect() async {
        cancelConnect()
        let old = tokens
        clearSession()
        phase = Self.phase(credentials: credentials, tokens: nil)
        if let token = old?.refreshToken ?? old?.accessToken {
            await GoogleAuth.revoke(token)
        }
    }

    private func clearSession() {
        Config.clearTokens()
        tokens = nil
        events = []
        calendars = []
        settings.accountEmail = nil
        saveSettings()
    }

    // MARK: Tape

    func toggleExpanded() {
        expanded.toggle()
        settings.expanded = expanded
        saveSettings()
        OverlayController.shared.apply(animated: true)
    }

    func setLightMode(_ on: Bool) {
        settings.lightMode = on
        saveSettings()
    }

    func setOverlayHidden(_ on: Bool) {
        overlayHidden = on
        settings.overlayHidden = on
        saveSettings()
        OverlayController.shared.apply(animated: true)
    }

    func statusTitle(at now: Date) -> String {
        switch phase {
        case .needsClient, .needsSignIn: return "set up"
        case .connecting: return "…"
        case .connected: break
        }
        if let current = events.first(where: { $0.contains(now) }) {
            let left = max(0, Int(current.end.timeIntervalSince(now) / 60))
            return left == 0 ? "now" : "\(left)m"
        }
        if let next = events.filter({ !$0.isAllDay && $0.start > now }).min(by: { $0.start < $1.start }) {
            let mins = max(0, Int(next.start.timeIntervalSince(now) / 60))
            if mins >= 60 { return "\(mins / 60)h" }
            return "\(mins)m"
        }
        return "–"
    }

    var timedEvents: [DayEvent] { events.filter { !$0.isAllDay } }
    var allDayEvents: [DayEvent] { events.filter(\.isAllDay) }

    /// First timed event start → last timed event end. No configured clock window.
    func dayWindow(on date: Date = Date()) -> (Date, Date) {
        let timed = timedEvents
        if let start = timed.map(\.start).min(),
           let end = timed.map(\.end).max(),
           end > start {
            return (start, end)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return (start, end)
    }

    func saveSettings() {
        Config.saveSettings(settings)
    }

    func setCalendarColor(_ color: CalendarColor, for id: String) {
        guard settings.calendarColors[id] != color.hex else { return }
        settings.calendarColors[id] = color.hex
        saveSettings()
    }

    func blockColor(for event: DayEvent, at now: Date) -> CalendarColor {
        settings.calendarColor(for: event.calendarID).block(
            past: !event.isAllDay && event.end <= now
        )
    }

    func toggleCalendar(_ id: String) {
        var hidden = settings.hidden
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        settings.hidden = hidden
        saveSettings()
        Task { await reload() }
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            openAtLogin = LoginItem.isEnabled
        } catch {
            lastError = "Couldn't change Open at login: \(error.localizedDescription)"
            openAtLogin = LoginItem.isEnabled
        }
    }

    // MARK: Sync

    func reload() async {
        guard phase == .connected, let creds = credentials, var tokens else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var token: String
            var list: [CalendarInfo]
            do {
                token = try await CalendarAPI.validToken(credentials: creds, tokens: &tokens)
                list = try await CalendarAPI.calendarList(token: token)
            } catch AuthError.sessionExpired where tokens.refreshToken != nil {
                // The access token can be revoked before it expires. Refresh once and retry.
                token = try await CalendarAPI.validToken(credentials: creds, tokens: &tokens, force: true)
                list = try await CalendarAPI.calendarList(token: token)
            }
            self.tokens = tokens

            let orderedIDs = list.sorted {
                if $0.primary != $1.primary { return $0.primary }
                return $0.id < $1.id
            }.map(\.id)
            var updated = settings
            var changed = updated.assignCalendarColors(to: orderedIDs)
            let email = list.first(where: \.primary)?.id
            if updated.accountEmail != email {
                updated.accountEmail = email
                changed = true
            }
            if changed {
                settings = updated
                saveSettings()
            }
            calendars = list.sorted {
                if $0.primary != $1.primary { return $0.primary }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            let hidden = settings.hidden
            let visible = list.filter { !hidden.contains($0.id) }
            let dayStart = Calendar.current.startOfDay(for: Date())
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            var collected: [DayEvent] = []
            try await withThrowingTaskGroup(of: [DayEvent].self) { group in
                for cal in visible {
                    group.addTask {
                        try await CalendarAPI.events(token: token, calendar: cal, start: dayStart, end: dayEnd)
                    }
                }
                for try await batch in group {
                    collected.append(contentsOf: batch)
                }
            }
            events = collected.sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
                return lhs.start < rhs.start
            }
            lastError = nil
        } catch let error as AuthError where error == .sessionExpired || error == .invalidClient {
            // The saved sign-in no longer works. Go back to Connect, keep the client.
            clearSession()
            phase = Self.phase(credentials: credentials, tokens: nil)
            lastError = error.localizedDescription
            OverlayController.shared.apply(animated: false)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
