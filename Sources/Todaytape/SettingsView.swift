import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SetupLinks {
    static let newProject = URL(string: "https://console.cloud.google.com/projectcreate")!
    static let enableCalendarAPI = URL(string: "https://console.cloud.google.com/flows/enableapi?apiid=calendar-json.googleapis.com")!
    static let branding = URL(string: "https://console.cloud.google.com/auth/branding")!
    static let audience = URL(string: "https://console.cloud.google.com/auth/audience")!
    static let clients = URL(string: "https://console.cloud.google.com/auth/clients")!
    static let guide = URL(string: "https://github.com/ProximoBinks/todaytape/blob/main/docs/google-setup.md")!
}

/// Settings and first-run setup in one window. Before you're connected it walks
/// through the three Google steps; afterwards it shows calendars and appearance.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if state.phase == .connected {
                    connectedAccount
                    calendarsSection
                } else {
                    SetupSteps()
                }

                appearanceSection
                generalSection

                if let err = state.lastError {
                    ErrorBanner(message: err) { state.lastError = nil }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 440, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.phase == .connected ? "Todaytape" : "Set up Todaytape")
                    .font(.system(size: 18, weight: .semibold))
                Text(state.phase == .connected
                     ? "Today's Google Calendar on the edge of your screen."
                     : "Connect your own Google Calendar. About 5 minutes, once.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var connectedAccount: some View {
        section("Google account") {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.settings.accountEmail ?? "Connected")
                        .font(.system(size: 13, weight: .medium))
                        .textSelection(.enabled)
                    Text("Read-only access · client \(state.credentials?.displayID ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await state.reload() }
                }
                .disabled(state.isRefreshing)
                Button("Disconnect") {
                    Task { await state.disconnect() }
                }
            }
        }
    }

    @ViewBuilder
    private var calendarsSection: some View {
        section("Calendars") {
            if state.calendars.isEmpty {
                Text(state.isRefreshing ? "Loading your calendars…" : "No calendars yet. Click Refresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tick the calendars to show. Click a swatch to change its colour on the tape (Google Calendar isn't changed).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(state.calendars) { cal in
                    CalendarSettingsRow(calendar: cal)
                }
            }
        }
    }

    private var appearanceSection: some View {
        section("Appearance") {
            Picker("Appearance", selection: Binding(
                get: { state.settings.lightMode },
                set: { state.setLightMode($0) }
            )) {
                Text("Dark").tag(false)
                Text("Light").tag(true)
            }
            // Avoid the native segmented control's repeated fitting-size
            // invalidation on macOS 26, including in closed windows.
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
        }
    }

    private var generalSection: some View {
        section("General") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open at login")
                        .font(.system(size: 12, weight: .medium))
                    Text("Start Todaytape when you log in to your Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.openAtLogin },
                    set: { state.setOpenAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            if state.credentials != nil {
                HStack {
                    Text("Google client \(state.credentials?.displayID ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove client…") { confirmRemoveClient() }
                        .controlSize(.small)
                }
            }
        }
    }

    private func confirmRemoveClient() {
        let alert = NSAlert()
        alert.messageText = "Remove your Google client?"
        alert.informativeText = "Todaytape will disconnect and forget the client ID and secret. Your calendar colours and appearance are kept."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            state.removeClient()
        }
    }
}

// MARK: - Setup steps

private struct SetupSteps: View {
    @EnvironmentObject private var state: AppState
    @State private var showManual = false
    @State private var clientID = ""
    @State private var clientSecret = ""

    private var hasClient: Bool { state.credentials != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Todaytape reads your calendar with a Google client that you own, so your data goes straight from Google to your Mac. Google asks you to create that client once.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            step(1, "Prepare a Google Cloud project", done: hasClient) {
                bullet("Create a project (any name), then enable the Google Calendar API.") {
                    linkButton("New project", SetupLinks.newProject)
                    linkButton("Enable Calendar API", SetupLinks.enableCalendarAPI)
                }
                bullet("Open Google Auth Platform and click Get started. Choose External, add your email, agree, Create.") {
                    linkButton("Branding", SetupLinks.branding)
                }
                bullet("Under Audience, add your Gmail address as a test user. Leave the app in Testing.") {
                    linkButton("Audience", SetupLinks.audience)
                }
            }

            step(2, "Add your Desktop client", done: hasClient) {
                bullet("Clients → Create client → Application type: Desktop app → Create. Click Download JSON before you close the dialog: Google shows the secret once.") {
                    linkButton("Clients", SetupLinks.clients)
                }
                if let creds = state.credentials {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Client \(creds.displayID) saved")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Replace…") { importJSON() }
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            importJSON()
                        } label: {
                            Label("Import client JSON…", systemImage: "doc.badge.plus")
                        }
                        .keyboardShortcut("o", modifiers: .command)
                        Button(showManual ? "Hide fields" : "Paste instead") {
                            showManual.toggle()
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 2)
                    if showManual {
                        manualEntry
                    }
                }
            }

            step(3, "Connect Google Calendar", done: state.phase == .connected) {
                Text("Your browser opens Google's sign-in. Pick the account you added as a test user. Google warns that the app isn't verified: it's your own app, so click Continue.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if state.phase == .connecting {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Google in your browser…")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Cancel") { state.cancelConnect() }
                    } else {
                        Button {
                            Task { await state.connect() }
                        } label: {
                            Text("Connect Google Calendar")
                                .frame(minWidth: 180)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!hasClient)
                    }
                }
                .padding(.top, 2)
            }

            Link("Step-by-step guide with screenshots", destination: SetupLinks.guide)
                .font(.system(size: 12))
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Client ID  (….apps.googleusercontent.com)", text: $clientID)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            SecureField("Client secret", text: $clientSecret)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            Button("Save client") {
                state.saveClient(id: clientID, secret: clientSecret)
                if state.credentials != nil {
                    clientID = ""
                    clientSecret = ""
                    showManual = false
                }
            }
            .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty
                      || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, 4)
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.title = "Choose the client JSON you downloaded from Google"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            state.importClient(from: url)
        }
    }

    private func step(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.primary.opacity(0.85))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bullet(_ text: String, @ViewBuilder links: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) { links() }
        }
    }

    private func linkButton(_ title: String, _ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .font(.system(size: 11))
        }
        .controlSize(.small)
        .help(url.absoluteString)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        content()
    }
}
