import Contacts
import CoreLocation
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

nonisolated struct FamiliarContact: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]
    let organizationName: String?
}

nonisolated protocol FamiliarContactsServicing: Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func search(query: String, limit: Int) async throws -> [FamiliarContact]
}

actor FamiliarContactsService: FamiliarContactsServicing {
    private let store = CNContactStore()

    func availability() -> FamiliarCapabilityAvailability {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: .available
        case .notDetermined: .requestable
        case .denied, .restricted: .unavailable(reason: "联系人权限不可用，请在系统设置中允许访问。")
        @unknown default: .unavailable(reason: "联系人权限状态未知。")
        }
    }

    func requestAccess() async throws {
        switch availability() {
        case .available: return
        case .unavailable(let reason): throw FamiliarToolRegistryError.capabilityUnavailable(reason)
        case .requestable:
            guard try await store.requestAccess(for: .contacts) else {
                throw FamiliarToolRegistryError.capabilityUnavailable("用户未允许联系人访问。")
            }
        }
    }

    func search(query: String, limit: Int) async throws -> [FamiliarContact] {
        try Task.checkCancellation()
        guard case .available = availability() else {
            throw FamiliarToolRegistryError.capabilityUnavailable("联系人权限尚未授予。")
        }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(matchingName: normalized)
        var values: [FamiliarContact] = []
        try store.enumerateContacts(with: request) { contact, stop in
            values.append(FamiliarContact(
                id: contact.identifier,
                displayName: CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName,
                phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                emailAddresses: contact.emailAddresses.map { String($0.value) },
                organizationName: contact.organizationName.isEmpty ? nil : contact.organizationName
            ))
            if values.count == limit { stop.pointee = true }
        }
        return values
    }
}

nonisolated struct FamiliarContactsSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String; let limit: Int? }
    let service: any FamiliarContactsServicing
    let manifest = FamiliarToolManifest(
        name: "contacts_search",
        title: "搜索联系人",
        description: "在用户授权的联系人中按姓名搜索，最多返回 20 条及回答所需的最小字段。",
        parameters: .init(type: .object, properties: [
            "query": .init(type: .string, description: "联系人姓名"),
            "limit": .init(type: .integer, description: "1 到 20")
        ], required: ["query"]),
        effect: .read,
        risk: .sensitive,
        requirements: [.contactsRead],
        dataDomains: ["contacts"],
        privacyLabels: ["contacts"],
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let values = try await service.search(query: input.query, limit: min(max(input.limit ?? 10, 1), 20))
        let records = values.map { contact in
            FamiliarToolPresentationPayload.Record(id: contact.id, fields: [
                .init(name: "name", value: contact.displayName),
                .init(name: "phones", value: contact.phoneNumbers.joined(separator: ", ")),
                .init(name: "emails", value: contact.emailAddresses.joined(separator: ", ")),
                .init(name: "organization", value: contact.organizationName ?? "")
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: values,
            presentation: .recordCollection(.init(
                summary: "找到 \(values.count) 位联系人。",
                recordType: "contact",
                records: records
            ))
        )))
    }
}

nonisolated struct FamiliarLocationSnapshot: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

@MainActor
protocol FamiliarLocationServicing: AnyObject, Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func currentLocation() async throws -> FamiliarLocationSnapshot
}

@MainActor
final class FamiliarLocationService: NSObject, FamiliarLocationServicing, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<FamiliarLocationSnapshot, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func availability() -> FamiliarCapabilityAvailability {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .available
        case .notDetermined: .requestable
        case .denied, .restricted: .unavailable(reason: "位置权限不可用，请在系统设置中允许访问。")
        @unknown default: .unavailable(reason: "位置权限状态未知。")
        }
    }

    func requestAccess() async throws {
        switch availability() {
        case .available: return
        case .unavailable(let reason): throw FamiliarToolRegistryError.capabilityUnavailable(reason)
        case .requestable:
            guard authorizationContinuation == nil else {
                throw FamiliarLocationError.requestInProgress
            }
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentLocation() async throws -> FamiliarLocationSnapshot {
        try await requestAccess()
        guard locationContinuation == nil else { throw FamiliarLocationError.requestInProgress }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.locationContinuation?.resume(throwing: CancellationError())
                self?.locationContinuation = nil
                self?.manager.stopUpdatingLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        switch availability() {
        case .available:
            authorizationContinuation = nil
            continuation.resume()
        case .unavailable(let reason):
            authorizationContinuation = nil
            continuation.resume(throwing: FamiliarToolRegistryError.capabilityUnavailable(reason))
        case .requestable:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: FamiliarLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}

nonisolated enum FamiliarLocationError: LocalizedError, Sendable {
    case requestInProgress
    var errorDescription: String? { "已有一个位置请求正在进行。" }
}

nonisolated struct FamiliarCurrentLocationTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let service: any FamiliarLocationServicing
    let manifest = FamiliarToolManifest(
        name: "current_location",
        title: "获取当前位置",
        description: "在前台单次获取当前位置，不持续跟踪、不后台定位。",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .sensitive,
        requirements: [.locationWhenInUse],
        dataDomains: ["location.current"],
        privacyLabels: ["precise-location"],
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let value = try await service.currentLocation()
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: value,
            presentation: .scalar(.init(
                summary: "已获取一次当前位置。",
                label: "latitude, longitude",
                value: "\(value.latitude), \(value.longitude)"
            ))
        )))
    }
}

@MainActor
protocol FamiliarClipboardServicing: AnyObject, Sendable {
    func readText() async -> String?
    func writeText(_ text: String?) async
}

@MainActor
final class FamiliarClipboardService: FamiliarClipboardServicing, @unchecked Sendable {
    func readText() -> String? {
#if os(iOS)
        UIPasteboard.general.string
#else
        NSPasteboard.general.string(forType: .string)
#endif
    }

    func writeText(_ text: String?) {
#if os(iOS)
        UIPasteboard.general.string = text
#else
        NSPasteboard.general.clearContents()
        if let text { NSPasteboard.general.setString(text, forType: .string) }
#endif
    }
}

nonisolated struct FamiliarClipboardReadTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Output: Encodable { let text: String }
    let service: any FamiliarClipboardServicing
    let manifest = FamiliarToolManifest(
        name: "clipboard_read",
        title: "读取剪贴板",
        description: "经用户确认后读取当前系统剪贴板中的文本。",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .sensitive,
        requirements: [],
        dataDomains: ["clipboard"],
        privacyLabels: ["clipboard"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .action(FamiliarActionProposal(
            title: "允许读取剪贴板？",
            fields: [],
            target: "clipboard",
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "剪贴板文本会进入当前 Agent Run 的模型上下文。",
            undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey,
            execute: {
                let text = await service.readText() ?? ""
                return .init(envelope: try FamiliarToolResultEnvelope(
                    model: Output(text: text),
                    presentation: .document(.init(
                        summary: text.isEmpty ? "剪贴板中没有文本。" : "已读取剪贴板文本。",
                        title: "Clipboard",
                        text: text,
                        mimeType: "text/plain"
                    ))
                ))
            },
            undo: nil
        ))
    }
}

nonisolated struct FamiliarClipboardWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let text: String }
    private struct Output: Encodable { let written: Bool; let characterCount: Int }
    private struct UndoOutput: Encodable { let restored: Bool }
    let service: any FamiliarClipboardServicing
    let manifest = FamiliarToolManifest(
        name: "clipboard_write",
        title: "写入剪贴板",
        description: "经用户确认后把文本写入系统剪贴板，并可在当前 App 会话中恢复旧值。",
        parameters: .init(type: .object, properties: [
            "text": .init(type: .string, description: "要写入剪贴板的文本")
        ], required: ["text"]),
        effect: .reversibleWrite,
        risk: .sensitive,
        requirements: [],
        dataDomains: ["clipboard"],
        privacyLabels: ["clipboard"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let previous = await service.readText()
        return .action(FamiliarActionProposal(
            title: "写入剪贴板",
            fields: [.init(id: "text", label: "Text", type: .text, value: input.text)],
            target: "clipboard",
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "将替换当前系统剪贴板文本。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            execute: {
                await service.writeText(input.text)
                return .init(envelope: try FamiliarToolResultEnvelope(
                    model: Output(written: true, characterCount: input.text.count),
                    presentation: .mutationReceipt(.init(
                        summary: "已写入剪贴板。",
                        operation: "clipboardWrite",
                        targetIdentifier: "clipboard",
                        succeeded: true,
                        undoAvailable: true
                    ))
                ))
            },
            undo: {
                await service.writeText(previous)
                return .init(envelope: try FamiliarToolResultEnvelope(
                    model: UndoOutput(restored: true),
                    presentation: .mutationReceipt(.init(
                        summary: "已恢复原剪贴板文本。",
                        operation: "clipboardRestore",
                        targetIdentifier: "clipboard",
                        succeeded: true,
                        undoAvailable: false
                    ))
                ))
            }
        ))
    }
}

nonisolated struct FamiliarPrepareShareTool: FamiliarTool {
    struct Input: Decodable, Sendable { let title: String?; let text: String }
    private struct Output: Encodable { let title: String?; let text: String; let requiresUserAction: Bool }
    let manifest = FamiliarToolManifest(
        name: "prepare_share",
        title: "准备系统分享",
        description: "准备要分享的文本。Familiar 不会自动发送；用户仍需点击回答下方的系统分享按钮并选择目标。",
        parameters: .init(type: .object, properties: [
            "title": .init(type: .string, description: "可选标题"),
            "text": .init(type: .string, description: "要分享的文本")
        ], required: ["text"]),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["share.payload"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let output = Output(title: input.title, text: input.text, requiresUserAction: true)
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: output,
            presentation: .document(.init(
                summary: "分享内容已准备好，仍需用户主动打开系统分享。",
                title: input.title ?? "Share",
                text: input.text,
                mimeType: "text/plain"
            ))
        )))
    }
}

nonisolated struct FamiliarDeviceCapabilityProvider: FamiliarCapabilityProviding {
    let eventKit: any FamiliarEventKitServicing
    let contacts: any FamiliarContactsServicing
    let location: any FamiliarLocationServicing

    func availability(for requirement: FamiliarCapabilityRequirement) async -> FamiliarCapabilityAvailability {
        switch requirement {
        case .calendarFullAccess, .remindersFullAccess:
            await eventKit.availability(for: requirement)
        case .contactsRead:
            await contacts.availability()
        case .locationWhenInUse:
            await location.availability()
        }
    }

    func request(_ requirement: FamiliarCapabilityRequirement) async throws {
        switch requirement {
        case .calendarFullAccess, .remindersFullAccess:
            try await eventKit.request(requirement)
        case .contactsRead:
            try await contacts.requestAccess()
        case .locationWhenInUse:
            try await location.requestAccess()
        }
    }
}
