import AppKit
import SwiftUI

// MARK: - Window Controller

@MainActor
enum DriveConfigWindowController {
    private static var windowController: NSWindowController?

    static func show(auth: DriveAuth, client: DriveClient) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DriveConfigView(auth: auth, client: client)
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = NSSize(width: 480, height: 360)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Configure Google Drive"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 360))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        windowController?.close()
        windowController = nil
    }
}

// MARK: - View

struct DriveConfigView: View {
    private let auth: DriveAuth
    private let client: DriveClient

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var config: DriveConfig?
    @State private var statusMessage: String?
    @State private var isConnecting = false
    @State private var isTesting = false

    init(auth: DriveAuth, client: DriveClient) {
        self.auth = auth
        self.client = client
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            credentialsSection
            Divider()
            connectionSection
            Divider()
            storageSection
            Divider()
            feedSection
            Spacer()
            testConnectionButton
        }
        .padding(16)
        .frame(width: 480)
        .onAppear { loadConfig() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OAuth Credentials")
                .font(.headline)

            Form {
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
            }

            HStack {
                Link("How to obtain these →", destination: URL(string: "https://github.com/benatespina/susurro#drive-setup")!)
                    .font(.caption)
                Spacer()
                Button("Save") { saveCredentials() }
                    .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection")
                .font(.headline)

            HStack(spacing: 6) {
                Circle()
                    .fill(config?.isConnected == true ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(config?.isConnected == true ? "Connected" : "Not connected")
                    .foregroundStyle(.secondary)
            }

            Button(isConnecting ? "Connecting…" : "Connect Google Drive") {
                Task { await connectDrive() }
            }
            .disabled(
                isConnecting ||
                clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if let msg = statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Storage")
                .font(.headline)
            HStack {
                Text("Folder:")
                    .foregroundStyle(.secondary)
                Text(config?.folderID != nil ? "Susurro Library" : "Not configured")
                    .foregroundStyle(config?.folderID != nil ? .primary : .secondary)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feed")
                .font(.headline)

            if let feedURL = config?.feedURL() {
                HStack {
                    Text(feedURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(feedURL.absoluteString, forType: .string)
                    }
                    .controlSize(.small)
                }
            } else {
                Text("Feed URL will appear here after first publish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testConnectionButton: some View {
        HStack {
            Spacer()
            Button(isTesting ? "Testing…" : "Test Connection") {
                Task { await testConnection() }
            }
            .disabled(isTesting || config?.isConnected != true)
        }
    }

    // MARK: - Actions

    private func loadConfig() {
        config = DriveConfig.load()
        clientID = config?.clientID ?? ""
        // Don't populate clientSecret from Keychain into a TextField for security.
    }

    private func saveCredentials() {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else { return }

        let updated = DriveConfig(
            clientID: trimmedID,
            clientSecret: trimmedSecret,
            refreshToken: config?.refreshToken,
            accessToken: config?.accessToken,
            accessTokenExpiry: config?.accessTokenExpiry,
            folderID: config?.folderID,
            feedFileID: config?.feedFileID
        )
        DriveConfig.save(updated)
        config = DriveConfig.load()
        statusMessage = "Credentials saved."
    }

    private func connectDrive() async {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else { return }

        isConnecting = true
        statusMessage = nil
        defer { isConnecting = false }

        do {
            let (refreshToken, accessToken, expiry) = try await auth.connect(
                clientID: trimmedID,
                clientSecret: trimmedSecret
            )

            var updated = DriveConfig(
                clientID: trimmedID,
                clientSecret: trimmedSecret,
                refreshToken: refreshToken,
                accessToken: accessToken,
                accessTokenExpiry: expiry,
                folderID: config?.folderID,
                feedFileID: config?.feedFileID
            )
            DriveConfig.save(updated)

            // Create "Susurro Library" folder if not yet configured.
            if updated.folderID == nil {
                let folderID = try await client.createFolder(name: "Susurro Library", parentID: "root")
                updated = DriveConfig(
                    clientID: trimmedID,
                    clientSecret: trimmedSecret,
                    refreshToken: refreshToken,
                    accessToken: accessToken,
                    accessTokenExpiry: expiry,
                    folderID: folderID,
                    feedFileID: nil
                )
                DriveConfig.save(updated)
            }

            config = DriveConfig.load()
            statusMessage = "Connected successfully."
        } catch DriveAuthError.userCancelled {
            statusMessage = "Connection cancelled."
        } catch {
            statusMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func testConnection() async {
        guard let folderID = config?.folderID else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let meta = try await client.headFile(fileID: folderID)
            statusMessage = meta != nil ? "Connection OK — folder '\(meta!.name)' accessible." : "Folder not found on Drive."
        } catch {
            statusMessage = "Test failed: \(error.localizedDescription)"
        }
    }
}
