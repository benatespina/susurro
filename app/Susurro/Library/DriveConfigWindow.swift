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
        hosting.preferredContentSize = NSSize(width: 480, height: 420)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Configure Google Drive"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 420))
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
    @State private var coverImageURL: String = ""
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
            feedSection
            Divider()
            coverImageSection
            Spacer()
            testConnectionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(width: 480)
        .onAppear { loadConfig() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OAuth Credentials")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Client ID")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("", text: $clientID)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Link("How to obtain this →", destination: URL(string: "https://github.com/benatespina/susurro#drive-setup")!)
                    .font(.caption)
                Spacer()
                Button("Save") { saveCredentials() }
                    .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

            if config?.isConnected == true {
                Button("Disconnect Google Drive") {
                    disconnectDrive()
                }
            } else {
                Button(isConnecting ? "Connecting…" : "Connect Google Drive") {
                    Task { await connectDrive() }
                }
                .disabled(
                    isConnecting ||
                    clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feed")
                .font(.headline)

            if let feedURL = config?.feedURL() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("", text: .constant(feedURL.absoluteString))
                            .textFieldStyle(.roundedBorder)
                            .truncationMode(.middle)
                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(feedURL.absoluteString, forType: .string)
                        }
                    }
                }
            } else {
                Text("Feed URL will appear here after first publish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var coverImageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover Artwork")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cover Image URL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/cover.png", text: $coverImageURL)
                    .textFieldStyle(.roundedBorder)
                Text("HTTPS URL to a square JPEG or PNG image (≥ 1400 × 1400 px) required for Apple Podcasts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Save") { saveCoverImage() }
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
        coverImageURL = config?.coverImageURLString ?? ""
    }

    private func saveCredentials() {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        let trimmedCoverURL = coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = DriveConfig(
            clientID: trimmedID,
            clientSecret: "",
            refreshToken: config?.refreshToken,
            accessToken: config?.accessToken,
            accessTokenExpiry: config?.accessTokenExpiry,
            folderID: config?.folderID,
            feedFileID: config?.feedFileID,
            coverImageURLString: trimmedCoverURL.isEmpty ? nil : trimmedCoverURL
        )
        DriveConfig.save(updated)
        config = DriveConfig.load()
        statusMessage = "Credentials saved."
    }

    private func saveCoverImage() {
        let trimmedURL = coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = DriveConfig(
            clientID: trimmedID.isEmpty ? (config?.clientID ?? "") : trimmedID,
            clientSecret: config?.clientSecret ?? "",
            refreshToken: config?.refreshToken,
            accessToken: config?.accessToken,
            accessTokenExpiry: config?.accessTokenExpiry,
            folderID: config?.folderID,
            feedFileID: config?.feedFileID,
            coverImageURLString: trimmedURL.isEmpty ? nil : trimmedURL
        )
        DriveConfig.save(updated)
        config = DriveConfig.load()
        coverImageURL = config?.coverImageURLString ?? ""
        statusMessage = "Cover image URL saved."
    }

    private func connectDrive() async {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        isConnecting = true
        statusMessage = nil
        defer { isConnecting = false }

        // Capture prior persisted values before OAuth flow may alter state.
        let prior = DriveConfig.load()
        let priorFeedFileID = prior?.feedFileID
        let priorFolderID = prior?.folderID ?? config?.folderID
        let priorCoverImageURLString = prior?.coverImageURLString

        do {
            let (refreshToken, accessToken, expiry) = try await auth.connect(
                clientID: trimmedID,
                clientSecret: ""
            )

            let base = DriveConfig(
                clientID: trimmedID,
                clientSecret: "",
                refreshToken: refreshToken,
                accessToken: accessToken,
                accessTokenExpiry: expiry,
                folderID: priorFolderID,
                feedFileID: priorFeedFileID,
                coverImageURLString: priorCoverImageURLString
            )
            var updated = base
            DriveConfig.save(updated)

            // Reuse the existing root folder if present so reconnecting after a local
            // wipe doesn't create a duplicate per OAuth connect.
            if updated.folderID == nil {
                let folderID: String
                if let existing = try? await client.findFolderByName(DriveConfig.folderName, parentID: "root") {
                    folderID = existing
                } else {
                    folderID = try await client.createFolder(name: DriveConfig.folderName, parentID: "root")
                }
                updated = base.copying(
                    refreshToken: refreshToken,
                    accessToken: accessToken,
                    accessTokenExpiry: expiry,
                    folderID: folderID
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

    private func disconnectDrive() {
        DriveConfig.clearTokensOnly()
        config = DriveConfig.load()
        statusMessage = "Disconnected. Reconnect to resume publishing."
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
