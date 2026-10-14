import AppKit
import SwiftUI

@main
struct TodaytapeApp: App {
    @ObservedObject private var state = AppState.shared

    init() {
        let args = CommandLine.arguments
        if args.contains("--version") {
            print("Todaytape \(Self.version)")
            exit(0)
        }
        if args.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        if args.contains("--logout") {
            Config.clearTokens()
            print("Signed out. Your Google client is still saved; connect again from Settings.")
            exit(0)
        }
        DispatchQueue.main.async {
            AppState.shared.start()
            OverlayController.shared.start()
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some Scene {
        MenuBarExtra {
            if state.phase == .connected {
                Button(state.expanded ? "Collapse" : "Expand") {
                    state.toggleExpanded()
                }
                .disabled(state.overlayHidden)
                Button(state.overlayHidden ? "Show" : "Hide") {
                    state.setOverlayHidden(!state.overlayHidden)
                }
                Button("Refresh") {
                    Task { await state.reload() }
                }
            } else {
                Button("Set up Todaytape…") {
                    OverlayController.shared.openSettings()
                }
            }
            Divider()
            Button("Settings…") {
                OverlayController.shared.openSettings()
            }
            .keyboardShortcut(",")
            Button("Quit Todaytape") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            StatusLabel(state: state)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    OverlayController.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct StatusLabel: View {
    @ObservedObject var state: AppState
    @State private var title = ""

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
            Text(title)
        }
        .onReceive(AppClock.shared.$now) { now in
            // The countdown is in minutes; redraw only when its text changes.
            let next = state.statusTitle(at: now)
            if title != next { title = next }
        }
        .onChange(of: state.statusTitle(at: AppClock.shared.now), initial: true) { _, next in
            if title != next { title = next }
        }
    }
}

enum Diagnostics {
    /// `Todaytape --dump` prints today's events from every calendar, for debugging.
    static func dump() {
        Config.migrateLegacyFolderIfNeeded()
        guard let creds = Config.loadCredentials() else {
            fputs("No Google client yet. Open Todaytape and follow the setup in Settings.\n", stderr)
            exit(1)
        }
        guard var tokens = Config.loadTokens() else {
            fputs("Not connected. Open Todaytape → Settings → Connect Google Calendar.\n", stderr)
            exit(1)
        }
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let token = try await CalendarAPI.validToken(credentials: creds, tokens: &tokens)
                let cals = try await CalendarAPI.calendarList(token: token)
                let start = Calendar.current.startOfDay(for: Date())
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                let time = DateFormatter()
                time.dateFormat = "HH:mm"
                for cal in cals {
                    let events = try await CalendarAPI.events(token: token, calendar: cal, start: start, end: end)
                    if events.isEmpty { continue }
                    print("## \(cal.title)")
                    for event in events {
                        let mark = event.isAllDay ? "all day" : "\(time.string(from: event.start))-\(time.string(from: event.end))"
                        print("- \(event.title)  (\(mark))")
                    }
                }
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            sem.signal()
        }
        sem.wait()
    }
}
