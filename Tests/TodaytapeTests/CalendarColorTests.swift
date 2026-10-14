import Foundation
import SwiftUI
import AppKit

private func expectTrue(_ value: Bool) { precondition(value) }
private func expectFalse(_ value: Bool) { precondition(!value) }
private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs) }
private func expectDifferent<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs != rhs) }
private func expectNil<T>(_ value: T?) { precondition(value == nil) }
private func expectAtLeast(_ lhs: Double, _ rhs: Double, _ message: String) { precondition(lhs >= rhs, message) }

@main
struct CalendarColorTests {
    static func main() throws {
        let tests = CalendarColorTests()
        try tests.testExistingSettingsMigrateWithoutLosingPreferences()
        tests.testAssignmentsSurviveReorderingHidingAndNewCalendars()
        try tests.testInvalidColourRecoversAndCustomColoursRoundTrip()
        tests.testTextContrastForPaletteCustomColoursAndPastEvents()
        tests.testOriginalBlueFadeAndHuePreservation()
        try tests.testClientJSONImport()
        try tests.testLegacySecretsAreReadButNeverWritten()
        tests.testGoogleErrorsMapToFixes()
        try tests.testLoopbackIgnoresStrayRequests()
        print("Passed: settings migration, stable assignments, persistence, colour validation, reference blue fade, hue preservation, contrast across 4,096 custom colours, client JSON import, legacy secret scrubbing, Google error mapping, and the sign-in redirect server.")
    }

    /// The redirect server must ignore requests without the right `state`
    /// (favicon fetches, preconnects, forged links) and hand back the real code.
    func testLoopbackIgnoresStrayRequests() throws {
        let done = DispatchSemaphore(value: 0)
        var failure: String?
        Task {
            do {
                func get(_ port: UInt16, _ path: String) async throws -> Int {
                    let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
                    return (response as? HTTPURLResponse)?.statusCode ?? 0
                }
                let server = LoopbackServer()
                let port = try await server.start(expectedState: "s123")
                async let code = server.waitForCode()
                let favicon = try await get(port, "/favicon.ico")
                let forged = try await get(port, "/?state=wrong&code=evil")
                let real = try await get(port, "/?state=s123&code=good")
                let received = try await code
                if favicon != 404 || forged != 404 || real != 200 || received != "good" {
                    failure = "loopback: favicon=\(favicon) forged=\(forged) real=\(real) code=\(received)"
                }

                let denied = LoopbackServer()
                let port2 = try await denied.start(expectedState: "s2")
                async let deniedCode = denied.waitForCode()
                _ = try await get(port2, "/?state=s2&error=access_denied")
                do {
                    _ = try await deniedCode
                    failure = "loopback: access_denied should throw"
                } catch let error as AuthError where error == .accessDenied {
                } catch {
                    failure = "loopback: wrong error \(error)"
                }

                let cancelled = LoopbackServer()
                _ = try await cancelled.start(expectedState: "s3")
                cancelled.cancel(with: .timedOut)
                do {
                    _ = try await cancelled.waitForCode()
                    failure = "loopback: cancel should throw"
                } catch let error as AuthError where error == .timedOut {
                } catch {
                    failure = "loopback: wrong cancel error \(error)"
                }
            } catch {
                failure = "loopback: \(error)"
            }
            done.signal()
        }
        if done.wait(timeout: .now() + 20) == .timedOut { failure = "loopback: timed out" }
        if let failure { preconditionFailure(failure) }
    }

    func testClientJSONImport() throws {
        let id = "123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com"
        // The file Google offers for a Desktop app client.
        let installed = Data(#"{"installed":{"client_id":"\#(id)","project_id":"todaytape-test","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","client_secret":"GOCSPX-test-secret","redirect_uris":["http://localhost"]}}"#.utf8)
        let creds = try ClientCredentials.parse(installed)
        expectEqual(creds.clientID, id)
        expectEqual(creds.clientSecret, "GOCSPX-test-secret")
        expectEqual(creds.displayID, "…789012")

        // Flat files (and our own credentials.json) still load, with whitespace trimmed.
        let flat = Data(#"{"client_id":"  \#(id)\n","client_secret":" s3cret "}"#.utf8)
        expectEqual(try ClientCredentials.parse(flat), ClientCredentials(clientID: id, clientSecret: "s3cret"))
        let saved = try JSONEncoder().encode(creds)
        expectEqual(try ClientCredentials.parse(saved), creds)

        func fails(_ json: String, with expected: ClientCredentials.ParseError) {
            do {
                _ = try ClientCredentials.parse(Data(json.utf8))
                preconditionFailure("expected \(expected)")
            } catch let error as ClientCredentials.ParseError {
                precondition("\(error)" == "\(expected)", "got \(error), expected \(expected)")
            } catch {
                preconditionFailure("unexpected \(error)")
            }
        }
        fails("not json", with: .notJSON)
        fails(#"{"web":{"client_id":"\#(id)","client_secret":"x"}}"#, with: .webClient)
        fails(#"{"installed":{"client_id":"\#(id)"}}"#, with: .missingFields)
        fails(#"{"client_id":"1234-abc","client_secret":"x"}"#, with: .badClientID)
    }

    func testLegacySecretsAreReadButNeverWritten() throws {
        let id = "1-a.apps.googleusercontent.com"
        let old = Data(#"{"clientID":"\#(id)","clientSecret":"GOCSPX-old","lightMode":true,"dayStartHour":8,"calendarColors":{"a":"65B8A6"}}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: old)
        expectTrue(settings.hasLegacyCredentials)
        expectEqual(settings.legacyCredentials, ClientCredentials(clientID: id, clientSecret: "GOCSPX-old"))
        expectTrue(settings.lightMode)
        expectEqual(settings.calendarColors["a"], "65B8A6")

        // Even before dropLegacyCredentials(), the secret must not be written back.
        let written = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        expectFalse(written.contains("GOCSPX"))
        expectFalse(written.contains("clientID"))
        settings.dropLegacyCredentials()
        expectFalse(settings.hasLegacyCredentials)
        expectNil(settings.legacyCredentials)
    }

    func testGoogleErrorsMapToFixes() {
        expectEqual(AuthError.from(status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#), .sessionExpired)
        expectEqual(AuthError.from(status: 401, body: #"{"error":"invalid_client"}"#), .invalidClient)
        expectEqual(AuthError.from(status: 403, body: #"{"error":{"code":403,"message":"Google Calendar API has not been used in project 123 before or it is disabled.","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}"#), .calendarAPIDisabled)
        expectEqual(AuthError.from(status: 401, body: #"{"error":{"code":401,"status":"UNAUTHENTICATED"}}"#), .sessionExpired)
        expectEqual(AuthError.from(status: 500, body: "boom"), .http(500, "boom"))
        for error in [AuthError.accessDenied, .invalidClient, .calendarAPIDisabled, .sessionExpired] {
            expectFalse((error.errorDescription ?? "").isEmpty)
        }
        // Form encoding must escape characters a client secret can contain.
        let body = String(decoding: GoogleAuth.form(["client_secret": "a+b/c=d&e"]), as: UTF8.self)
        expectEqual(body, "client_secret=a%2Bb%2Fc%3Dd%26e")
    }
    func testExistingSettingsMigrateWithoutLosingPreferences() throws {
        let data = Data(#"{"lightMode":true,"expanded":true,"hiddenCalendarIDs":["hidden"]}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)
        expectTrue(settings.lightMode)
        expectTrue(settings.expanded)
        expectEqual(settings.hidden, ["hidden"])
        expectTrue(settings.calendarColors.isEmpty)
        expectTrue(settings.assignCalendarColors(to: ["primary", "work", "home", "sport", "study", "family"]))
        expectEqual(Set(settings.calendarColors.values).count, 6)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        expectEqual(restored.calendarColors, settings.calendarColors)
        expectEqual(restored.hidden, settings.hidden)
    }

    func testAssignmentsSurviveReorderingHidingAndNewCalendars() {
        var settings = AppSettings()
        settings.assignCalendarColors(to: ["primary", "work", "home"])
        settings.calendarColors["work"] = "123456"
        let original = settings.calendarColors
        settings.hidden = ["home"]
        expectFalse(settings.assignCalendarColors(to: ["home", "work", "primary"]))
        settings.assignCalendarColors(to: ["new", "primary"])
        for (id, hex) in original { expectEqual(settings.calendarColors[id], hex) }
        expectDifferent(settings.calendarColors["new"], settings.calendarColors["primary"])
    }

    func testInvalidColourRecoversAndCustomColoursRoundTrip() throws {
        expectNil(CalendarColor(hex: "not-a-colour"))
        expectNil(CalendarColor(hex: "#12345678"))
        expectEqual(CalendarColor(hex: " #ab12ef ")?.hex, "AB12EF")
        var settings = AppSettings()
        settings.calendarColors = ["bad": "oops", "custom": "FAEBD7"]
        settings.assignCalendarColors(to: ["bad", "custom"])
        expectDifferent(settings.calendarColors["bad"], "oops")
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        expectEqual(restored.calendarColor(for: "custom").hex, "FAEBD7")
    }

    func testTextContrastForPaletteCustomColoursAndPastEvents() {
        let hexes = CalendarPalette.swatches.map(\.hex) + ["000000", "FFFFFF", "777777", "FF0000", "00FF00", "0000FF", "FFFF00"]
        for hex in hexes {
            let base = CalendarColor(hex: hex)!
            for past in [true, false] {
                let block = base.block(past: past)
                expectAtLeast(block.textContrast, 4.5, "\(hex), past=\(past)")
                if !past { expectEqual(block.hex, hex) }
            }
        }
    }
    func testOriginalBlueFadeAndHuePreservation() {
        expectEqual(CalendarColor(hex: "3896E8")!.block(past: true).hex, "9EC9EF")
        expectEqual(CalendarColor(hex: "000000")!.block(past: true).hex, "7D7D7D")
        expectEqual(CalendarColor(hex: "FFFFFF")!.block(past: true).hex, "FFFFFF")
        // Sweep all hue sectors and greys, including near-black/white values.
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let original = CalendarColor(hex: String(format: "%02X%02X%02X", red, green, blue))!
                    let faded = original.block(past: true)
                    expectAtLeast(faded.textContrast, 4.5, "Custom colour contrast")
                    let rgb = NSColor(original.color).usingColorSpace(.sRGB)!
                    let paleRGB = NSColor(faded.color).usingColorSpace(.sRGB)!
                    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                    let paleChannels = [paleRGB.redComponent, paleRGB.greenComponent, paleRGB.blueComponent]
                    let lightness = (channels.max()! + channels.min()!) / 2
                    let paleLightness = (paleChannels.max()! + paleChannels.min()!) / 2
                    expectAtLeast(paleLightness, lightness, "HSL lightness should increase")
                    precondition(abs(paleLightness - (lightness + (1 - lightness) * 109 / 222)) < 1.0 / 255)
                    if rgb.saturationComponent > 0.1 && paleRGB.saturationComponent > 0.05 {
                        let difference = abs(rgb.hueComponent - paleRGB.hueComponent)
                        precondition(min(difference, 1 - difference) < 0.015, "Hue drift")
                    }
                    if red == green && green == blue {
                        expectEqual(paleRGB.redComponent, paleRGB.greenComponent)
                        expectEqual(paleRGB.greenComponent, paleRGB.blueComponent)
                    }
                }
            }
        }
    }

}
