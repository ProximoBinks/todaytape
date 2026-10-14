import Foundation

/// Everything Todaytape stores lives in ~/.todaytape, readable only by you:
/// - credentials.json  your Google OAuth client (ID and secret)
/// - tokens.json       the sign-in Google returns
/// - settings.json     calendars, colours and appearance
///
/// Set `TODAYTAPE_HOME` to use another folder (handy for testing a fresh setup).
enum Config {
    static let folderName = ".todaytape"
    static let legacyFolderName = ".nowline"

    static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["TODAYTAPE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderName)
    }

    static var credentialsURL: URL { root.appendingPathComponent("credentials.json") }
    static var tokensURL: URL { root.appendingPathComponent("tokens.json") }
    static var settingsURL: URL { root.appendingPathComponent("settings.json") }

    static func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    /// One-time copy from the pre-release folder (~/.nowline). The old folder is left untouched.
    static func migrateLegacyFolderIfNeeded() {
        guard ProcessInfo.processInfo.environment["TODAYTAPE_HOME"] == nil else { return }
        let fm = FileManager.default
        let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(legacyFolderName)
        guard !fm.fileExists(atPath: root.path), fm.fileExists(atPath: legacy.path) else { return }
        guard (try? ensureRoot()) != nil else { return }
        for name in ["credentials.json", "tokens.json", "settings.json"] {
            let from = legacy.appendingPathComponent(name)
            let to = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.copyItem(at: from, to: to)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: to.path)
        }
    }

    // MARK: Credentials

    static func loadCredentials() -> ClientCredentials? {
        guard let data = try? Data(contentsOf: credentialsURL) else { return nil }
        return try? ClientCredentials.parse(data)
    }

    static func saveCredentials(_ creds: ClientCredentials) throws {
        try ensureRoot()
        try encode(creds, to: credentialsURL)
    }

    static func clearCredentials() {
        try? FileManager.default.removeItem(at: credentialsURL)
    }

    // MARK: Tokens

    static func loadTokens() -> OAuthTokens? {
        decode(OAuthTokens.self, from: tokensURL)
    }

    static func saveTokens(_ tokens: OAuthTokens) throws {
        try ensureRoot()
        try encode(tokens, to: tokensURL)
    }

    static func clearTokens() {
        try? FileManager.default.removeItem(at: tokensURL)
    }

    // MARK: Settings

    static func loadSettings() -> AppSettings {
        decode(AppSettings.self, from: settingsURL) ?? AppSettings()
    }

    static func saveSettings(_ settings: AppSettings) {
        try? ensureRoot()
        try? encode(settings, to: settingsURL)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct AppSettings: Codable {
    var hiddenCalendarIDs: [String] = []
    var expanded: Bool = false
    var lightMode: Bool = false
    var overlayHidden: Bool = false
    var calendarColors: [String: String] = [:]
    /// The connected Google account (the primary calendar's ID). Shown in Settings only.
    var accountEmail: String?

    /// Early builds kept the OAuth client in settings.json. Read once so it can
    /// move to credentials.json; never written back.
    private(set) var legacyClientID: String?
    private(set) var legacyClientSecret: String?

    init() {}

    enum CodingKeys: String, CodingKey {
        case hiddenCalendarIDs, expanded, lightMode, overlayHidden, calendarColors, accountEmail
        case legacyClientID = "clientID"
        case legacyClientSecret = "clientSecret"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenCalendarIDs = try c.decodeIfPresent([String].self, forKey: .hiddenCalendarIDs) ?? []
        expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        lightMode = try c.decodeIfPresent(Bool.self, forKey: .lightMode) ?? false
        overlayHidden = try c.decodeIfPresent(Bool.self, forKey: .overlayHidden) ?? false
        calendarColors = try c.decodeIfPresent([String: String].self, forKey: .calendarColors) ?? [:]
        accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail)
        legacyClientID = try c.decodeIfPresent(String.self, forKey: .legacyClientID)
        legacyClientSecret = try c.decodeIfPresent(String.self, forKey: .legacyClientSecret)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hiddenCalendarIDs, forKey: .hiddenCalendarIDs)
        try c.encode(expanded, forKey: .expanded)
        try c.encode(lightMode, forKey: .lightMode)
        try c.encode(overlayHidden, forKey: .overlayHidden)
        try c.encode(calendarColors, forKey: .calendarColors)
        try c.encodeIfPresent(accountEmail, forKey: .accountEmail)
    }

    /// A client found in an older settings.json, if any.
    var legacyCredentials: ClientCredentials? {
        let creds = ClientCredentials(clientID: legacyClientID ?? "", clientSecret: legacyClientSecret ?? "")
        return creds.isUsable ? creds : nil
    }

    var hasLegacyCredentials: Bool { legacyClientID != nil || legacyClientSecret != nil }

    mutating func dropLegacyCredentials() {
        legacyClientID = nil
        legacyClientSecret = nil
    }

    func calendarColor(for id: String) -> CalendarColor {
        calendarColors[id].flatMap(CalendarColor.init(hex:)) ?? CalendarPalette.fallback
    }

    /// Persist allocations so hiding, reordering or removing a calendar never
    /// recolours the others. Reuse the least-used swatch after six calendars.
    @discardableResult
    mutating func assignCalendarColors(to ids: [String]) -> Bool {
        var changed = false
        for id in ids where calendarColors[id].flatMap(CalendarColor.init(hex:)) == nil {
            let counts = Dictionary(grouping: calendarColors.values.compactMap(CalendarColor.init(hex:)), by: \.hex)
            let swatch = CalendarPalette.swatches.enumerated().min {
                let lhs = counts[$0.element.hex]?.count ?? 0
                let rhs = counts[$1.element.hex]?.count ?? 0
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }!.element
            calendarColors[id] = swatch.hex
            changed = true
        }
        return changed
    }

    var hidden: Set<String> {
        get { Set(hiddenCalendarIDs) }
        set { hiddenCalendarIDs = Array(newValue).sorted() }
    }
}
