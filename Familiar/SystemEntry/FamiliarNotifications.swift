import Foundation
import UIKit
import UserNotifications

nonisolated enum FamiliarNotificationRoute: Equatable, Sendable {
    case conversation(UUID)
    case run(UUID)

    var deepLink: FamiliarDeepLink {
        switch self {
        case .conversation(let id): .conversation(id)
        case .run(let id): .run(id)
        }
    }

    var encodedValue: String {
        switch self {
        case .conversation(let id): "conversation:\(id.uuidString)"
        case .run(let id): "run:\(id.uuidString)"
        }
    }

    init?(encodedValue: String) {
        let parts = encodedValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "conversation": self = .conversation(id)
        case "run": self = .run(id)
        default: return nil
        }
    }
}

enum FamiliarNotificationAuthorizationState: Equatable {
    case unknown
    case notDetermined
    case enabled
    case denied
}

@MainActor
enum FamiliarNotificationPreference {
    private static let key = "familiar.notifications.run_terminal.enabled.v1"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}

@MainActor
enum FamiliarNotificationService {
    static let categoryIdentifier = "FAMILIAR_RUN"
    static let routeUserInfoKey = "familiar.route"

    static func authorizationState() async -> FamiliarNotificationAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return state(for: settings.authorizationStatus)
    }

    static func setEnabled(_ enabled: Bool) async throws -> FamiliarNotificationAuthorizationState {
        guard enabled else {
            FamiliarNotificationPreference.setEnabled(false)
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            return await authorizationState()
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        }
        let updatedState = await authorizationState()
        FamiliarNotificationPreference.setEnabled(updatedState == .enabled)
        return updatedState
    }

    static func scheduleCompletedRun(conversationID: UUID, runID: UUID?) async {
        await schedule(
            identifier: "familiar.run.completed.\((runID ?? conversationID).uuidString)",
            title: String(localized: "notification.run.completed.title"),
            body: String(localized: "notification.run.completed.body"),
            route: runID.map(FamiliarNotificationRoute.run) ?? .conversation(conversationID)
        )
    }

    static func scheduleFailedRun(conversationID: UUID, runID: UUID?) async {
        await schedule(
            identifier: "familiar.run.failed.\((runID ?? conversationID).uuidString)",
            title: String(localized: "notification.run.failed.title"),
            body: String(localized: "notification.run.failed.body"),
            route: runID.map(FamiliarNotificationRoute.run) ?? .conversation(conversationID)
        )
    }

    static func route(from userInfo: [AnyHashable: Any]) -> FamiliarNotificationRoute? {
        guard let value = userInfo[routeUserInfoKey] as? String else { return nil }
        return FamiliarNotificationRoute(encodedValue: value)
    }

    static func registerCategory() {
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private static func schedule(
        identifier: String,
        title: String,
        body: String,
        route: FamiliarNotificationRoute
    ) async {
        guard FamiliarNotificationPreference.isEnabled,
              UIApplication.shared.applicationState != .active
        else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard state(for: settings.authorizationStatus) == .enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = "familiar.run"
        content.userInfo = [routeUserInfoKey: route.encodedValue]
        if settings.soundSetting == .enabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func state(for status: UNAuthorizationStatus) -> FamiliarNotificationAuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .enabled
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

final class FamiliarAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        FamiliarNotificationService.registerCategory()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let route = FamiliarNotificationService.route(from: response.notification.request.content.userInfo)
        else { return }
        FamiliarAppIntentHandoff.shared.submit(.deepLink(route.deepLink))
    }
}
