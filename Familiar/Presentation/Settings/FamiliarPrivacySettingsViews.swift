import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import HealthKit
import MusicKit
import Photos
import Speech
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct FamiliarAuthorizationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarAuthorizationRuleRecord.createdAt, order: .reverse) private var records: [FamiliarAuthorizationRuleRecord]
    @State private var errorMessage: String?

    private var activeRecords: [FamiliarAuthorizationRuleRecord] {
        records.filter { $0.revokedAt == nil && $0.expiresAt > Date() && $0.duration != .once }
    }

    var body: some View {
        List {
            if activeRecords.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.authorizations.empty", defaultValue: "No remembered authorizations"),
                    systemImage: "checkmark.shield"
                )
            } else {
                Section {
                    ForEach(activeRecords) { record in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(record.evidence.isEmpty ? record.capabilityID : record.evidence)
                                .font(FamiliarTypography.body.weight(.medium))
                            if record.duration != .always {
                                Text(record.targetKey)
                                    .font(FamiliarTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(durationLabel(record.duration))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .swipeActions {
                            Button(String(localized: "settings.authorizations.revoke", defaultValue: "Revoke"), role: .destructive) {
                                record.revokedAt = Date()
                                save()
                            }
                        }
                    }
                } footer: {
                    Text(String(localized: "settings.authorizations.footer", defaultValue: "Authorizations are scoped to a project, tool, and target. Destructive actions still require confirmation."))
                }

                Section {
                    Button(String(localized: "settings.authorizations.revoke_all", defaultValue: "Revoke All"), role: .destructive) {
                        let now = Date()
                        activeRecords.forEach { $0.revokedAt = now }
                        save()
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.authorizations", defaultValue: "Approved Actions"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "settings.error.title"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    /// Revoking an authorization must not appear to succeed when the save failed.
    private func save() {
        do { try modelContext.save() } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func durationLabel(_ duration: FamiliarAuthorizationDuration) -> String {
        switch duration {
        case .once: String(localized: "authorization.once", defaultValue: "Only Once")
        case .session: String(localized: "authorization.session", defaultValue: "Allow This Session")
        case .always: String(localized: "authorization.always", defaultValue: "Always Allow")
        }
    }
}

struct FamiliarStorageSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var usage: FamiliarStorageUsage?
    @State private var measuring = false
    @State private var error: String?
    @State private var revision = UUID()
    private let categories = ["settings.storage.attachments", "settings.storage.files", "settings.storage.workspaces", "settings.storage.runtime", "settings.storage.database", "settings.storage.other"]
    var body: some View {
        List {
            Section(String(localized: "settings.storage.overview")) {
                if let usage {
                    LabeledContent(String(localized: "settings.storage.conversations"), value: usage.conversations.formatted())
                    LabeledContent(String(localized: "settings.storage.messages"), value: usage.messages.formatted())
                    LabeledContent(String(localized: "settings.storage.file_records"), value: usage.files.formatted())
                    LabeledContent(String(localized: "settings.storage.file_versions"), value: usage.versions.formatted())
                    LabeledContent(String(localized: "settings.storage.total"), value: size(usage.total))
                }
                if measuring { ProgressView() }
                if let error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                Button(String(localized: "settings.storage.refresh")) { revision = UUID() }.disabled(measuring)
            }
            if let usage {
                Section {
                    ForEach(categories, id: \.self) { category in
                        LabeledContent(String(localized: String.LocalizationValue(category)), value: size(usage.bytes[category] ?? 0))
                    }
                    if usage.unreadableFiles > 0 { Text(String(localized: "settings.storage.incomplete")).font(.caption).foregroundStyle(.secondary) }
                } footer: { Text(String(localized: "settings.storage.measurement")) }
            }
            Section { Text(String(localized: "settings.storage.local.detail")).font(.subheadline).foregroundStyle(.secondary) }
        }
        .navigationTitle(String(localized: "settings.hub.storage")).navigationBarTitleDisplayMode(.inline)
        .task(id: revision) { await measure() }
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func measure() async {
        let expected = revision
        measuring = true; error = nil
        defer { if revision == expected { measuring = false } }
        do {
            let result = try await FamiliarStorageMeasurement.load(container: context.container)
            guard !Task.isCancelled, revision == expected else { return }
            usage = result
        } catch is CancellationError { }
        catch { if revision == expected && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct FamiliarPermissionsSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationState: FamiliarNotificationAuthorizationState = .unknown
    @State private var notificationsEnabled = FamiliarNotificationPreference.isEnabled
    @State private var isUpdatingNotifications = false
    @State private var healthRequestState: FamiliarHealthReadScope.RequestState = .notRequested

    var body: some View {
        List {
            Section {
                Toggle(
                    String(localized: "settings.notifications.run_terminal"),
                    isOn: Binding(
                        get: { notificationsEnabled },
                        set: { enabled in Task { await updateNotifications(enabled) } }
                    )
                )
                .disabled(isUpdatingNotifications)
                permissionRow(String(localized: "settings.permissions.calendar", defaultValue: "Calendar"), symbol: "calendar", status: eventStatus(.event))
                permissionRow(String(localized: "settings.permissions.reminders", defaultValue: "Reminders"), symbol: "checklist", status: eventStatus(.reminder))
                permissionRow(String(localized: "settings.permissions.contacts", defaultValue: "Contacts"), symbol: "person.crop.circle", status: contactsStatus)
                permissionRow(String(localized: "settings.permissions.location", defaultValue: "Location"), symbol: "location", status: locationStatus)
                permissionRow(String(localized: "settings.permissions.photos_add", defaultValue: "Add to Photos"), symbol: "photo.badge.plus", status: photoAddStatus)
                permissionRow(String(localized: "settings.permissions.photos_read", defaultValue: "Read Photo Metadata"), symbol: "photo.on.rectangle", status: photoReadStatus)
                permissionRow(String(localized: "settings.permissions.health", defaultValue: "Health Activity"), symbol: "heart.text.square", status: healthStatus)
                permissionRow(String(localized: "settings.permissions.music", defaultValue: "Apple Music"), symbol: "music.note", status: musicStatus)
                permissionRow(String(localized: "settings.permissions.bluetooth", defaultValue: "Bluetooth"), symbol: "dot.radiowaves.left.and.right", status: bluetoothStatus)
                permissionRow(String(localized: "settings.permissions.camera", defaultValue: "Camera"), symbol: "camera", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .video)))
                permissionRow(String(localized: "settings.permissions.microphone", defaultValue: "Microphone"), symbol: "mic", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .audio)))
                permissionRow(String(localized: "settings.permissions.speech", defaultValue: "Speech Recognition"), symbol: "waveform", status: speechStatus)
                permissionRow(String(localized: "settings.notifications.title"), symbol: "bell", status: notificationStatus)
            } footer: {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(String(localized: "settings.permissions.footer", defaultValue: "Familiar asks for access only when you use the related feature. Permissions are controlled by iOS."))
                    Text(String(localized: "settings.permissions.health_footer", defaultValue: "HealthKit never tells apps whether you denied a read request, so Familiar can only show whether it has asked. Missing values are never reported as zero."))
                }
            }

            Section {
                Button(String(localized: "settings.permissions.open", defaultValue: "Open Familiar in iOS Settings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.permissions", defaultValue: "Permissions"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationState = await FamiliarNotificationService.authorizationState()
            notificationsEnabled = FamiliarNotificationPreference.isEnabled && notificationState == .enabled
            healthRequestState = await FamiliarHealthReadScope.requestState()
        }
    }

    private func permissionRow(_ title: String, symbol: String, status: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(status).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventStatus(_ entity: EKEntityType) -> String {
        authorizationTitle(EKEventStore.authorizationStatus(for: entity).rawValue)
    }

    private func mediaStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var notificationStatus: String {
        switch notificationState {
        case .enabled: allowed
        case .denied: denied
        case .notDetermined, .unknown: notRequested
        }
    }

    private var contactsStatus: String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    /// HealthKit deliberately hides read denials, so the only honest states are
    /// "requested" and "not requested". Never render `allowed` here.
    private var healthStatus: String {
        switch healthRequestState {
        case .unavailable: String(localized: "settings.permissions.unsupported", defaultValue: "Not Supported")
        case .notRequested: notRequested
        case .requested: String(localized: "settings.permissions.requested", defaultValue: "Requested")
        }
    }

    private var musicStatus: String {
        switch MusicAuthorization.currentStatus {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var bluetoothStatus: String {
        switch CBManager.authorization {
        case .allowedAlways: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var photoReadStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: allowed
        case .limited: String(localized: "settings.permissions.limited", defaultValue: "Limited")
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var photoAddStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private func updateNotifications(_ enabled: Bool) async {
        guard !isUpdatingNotifications else { return }
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }
        do {
            notificationState = try await FamiliarNotificationService.setEnabled(enabled)
            notificationsEnabled = enabled && notificationState == .enabled
        } catch {
            notificationsEnabled = false
        }
    }

    private func authorizationTitle(_ rawValue: Int) -> String {
        switch EKAuthorizationStatus(rawValue: rawValue) {
        case .fullAccess, .authorized: allowed
        case .writeOnly: String(localized: "settings.permissions.write_only", defaultValue: "Write Only")
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        case nil: restricted
        @unknown default: restricted
        }
    }

    private var allowed: String { String(localized: "settings.permissions.allowed", defaultValue: "Allowed") }
    private var denied: String { String(localized: "settings.permissions.denied", defaultValue: "Denied") }
    private var restricted: String { String(localized: "settings.permissions.restricted", defaultValue: "Restricted") }
    private var notRequested: String { String(localized: "settings.permissions.not_requested", defaultValue: "Not Requested") }
}

struct FamiliarPrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                Label(String(localized: "settings.privacy.no_account"), systemImage: "person.crop.circle.badge.xmark")
                Label(String(localized: "settings.privacy.permission_tools"), systemImage: "hand.raised")
                Label(String(localized: "settings.privacy.native_private_data", defaultValue: "Contacts, one-time location, and clipboard data are used only by explicitly requested tools"), systemImage: "iphone.and.arrow.forward")
                Label(String(localized: "settings.privacy.local_history"), systemImage: "internaldrive")
                Label(String(localized: "settings.privacy.local_documents"), systemImage: "doc.text.magnifyingglass")
                Label(String(localized: "settings.privacy.remote_images"), systemImage: "photo.badge.exclamationmark")
                Label(String(localized: "settings.privacy.web_tools"), systemImage: "network")
            }
        }
        .navigationTitle(String(localized: "settings.privacy.data_handling"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
