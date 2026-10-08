import CoreBluetooth
import Foundation

// MARK: - CoreBluetooth

nonisolated struct FamiliarBluetoothPeripheral: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String?
    let rssi: Int
    let advertisedServiceUUIDs: [String]
    let connectable: Bool?
}

@MainActor
protocol FamiliarBluetoothServicing: AnyObject, Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func scan(serviceUUIDs: [String], duration: TimeInterval) async throws -> [FamiliarBluetoothPeripheral]
}

/// The native manager boundary lets lifecycle regressions drive real service logic.
@MainActor
protocol FamiliarBluetoothCentral: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
}

extension CBCentralManager: FamiliarBluetoothCentral {}

nonisolated enum FamiliarBluetoothServices {
    static func validate(_ values: [String]) throws {
        guard (FamiliarToolDefaults.BluetoothScan.minimumServiceUUIDs...FamiliarToolDefaults.BluetoothScan.maximumServiceUUIDs).contains(values.count) else {
            throw FamiliarAppleDeviceToolError.bluetoothServicesRequired
        }
        for value in values {
            let compact = (value.count == 4 || value.count == 8) && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
            let full = value.count == 36 && UUID(uuidString: value) != nil
            guard compact || full else { throw FamiliarAppleDeviceToolError.invalidBluetoothServiceUUID }
        }
    }
}

@MainActor
final class FamiliarBluetoothService: NSObject, FamiliarBluetoothServicing, CBCentralManagerDelegate, @unchecked Sendable {
    private var manager: (any FamiliarBluetoothCentral)?
    private let authorization: () -> CBManagerAuthorization
    private let makeManager: (any CBCentralManagerDelegate) -> any FamiliarBluetoothCentral
    private var scanTask: Task<Void, Never>?
    private var scanID: UUID?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var authorizationID: UUID?
    private var scanContinuation: CheckedContinuation<[FamiliarBluetoothPeripheral], Error>?
    private var discovered: [UUID: FamiliarBluetoothPeripheral] = [:]

    init(
        authorization: @escaping () -> CBManagerAuthorization = { CBManager.authorization },
        makeManager: @escaping (any CBCentralManagerDelegate) -> any FamiliarBluetoothCentral = {
            CBCentralManager(delegate: $0, queue: .main)
        }
    ) {
        self.authorization = authorization
        self.makeManager = makeManager
        super.init()
    }

    func availability() -> FamiliarCapabilityAvailability {
        switch authorization() {
        case .allowedAlways:
            if let manager, manager.state != .poweredOn, manager.state != .unknown, manager.state != .resetting {
                return .unavailable(reason: stateDescription(manager.state))
            }
            return .available
        case .notDetermined: return .requestable
        case .denied, .restricted: return .unavailable(reason: "蓝牙权限不可用，请在系统设置中允许访问。")
        @unknown default: return .unavailable(reason: "蓝牙权限状态未知。")
        }
    }

    func requestAccess() async throws {
        try Task.checkCancellation()
        if case .unavailable(let reason) = availability() {
            throw FamiliarToolRegistryError.capabilityUnavailable(reason)
        }
        guard authorizationContinuation == nil else { throw FamiliarAppleDeviceToolError.requestInProgress }
        let id = UUID()
        // CBCentralManager reports .unknown until its first delegate update, even
        // when permission was granted previously. Register before constructing it.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                authorizationID = id
                authorizationContinuation = continuation
                manager = manager ?? makeManager(self)
                centralStateDidChange()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.authorizationID == id else { return }
                self?.authorizationID = nil
                self?.authorizationContinuation?.resume(throwing: CancellationError())
                self?.authorizationContinuation = nil
            }
        }
        try Task.checkCancellation()
    }

    func scan(serviceUUIDs: [String], duration: TimeInterval) async throws -> [FamiliarBluetoothPeripheral] {
        try FamiliarBluetoothServices.validate(serviceUUIDs)
        try await requestAccess()
        try Task.checkCancellation()
        guard scanContinuation == nil else { throw FamiliarAppleDeviceToolError.requestInProgress }
        let uuids = serviceUUIDs.map(CBUUID.init(string:))
        discovered = [:]
        let boundedDuration = min(
            max(duration, FamiliarToolDefaults.BluetoothScan.minimumDuration),
            FamiliarToolDefaults.BluetoothScan.maximumDuration
        )
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                scanID = id
                scanContinuation = continuation
                manager?.scanForPeripherals(
                    withServices: uuids,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
                scanTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(boundedDuration)) } catch { return }
                    guard self?.scanID == id else { return }
                    self?.finishScan()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.scanID == id else { return }
                self?.cancelScan()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { centralStateDidChange() }

    func centralStateDidChange() {
        guard let manager else { return }
        if let continuation = authorizationContinuation {
            switch manager.state {
            case .poweredOn where authorization() == .allowedAlways:
                authorizationID = nil
                authorizationContinuation = nil
                continuation.resume()
            case .unknown, .resetting:
                break
            default:
                authorizationID = nil
                authorizationContinuation = nil
                continuation.resume(throwing: FamiliarToolRegistryError.capabilityUnavailable(stateDescription(manager.state)))
            }
        }
        if scanContinuation != nil, manager.state != .poweredOn, manager.state != .unknown, manager.state != .resetting {
            failScan(FamiliarToolRegistryError.capabilityUnavailable(stateDescription(manager.state)))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        discovered[peripheral.identifier] = FamiliarBluetoothPeripheral(
            id: peripheral.identifier.uuidString,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            advertisedServiceUUIDs: advertised,
            connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        )
    }

    private func finishScan() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        manager?.stopScan()
        guard let continuation = scanContinuation else { return }
        scanContinuation = nil
        continuation.resume(returning: discovered.values.sorted { $0.rssi > $1.rssi })
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        manager?.stopScan()
        guard let continuation = scanContinuation else { return }
        scanContinuation = nil
        continuation.resume(throwing: CancellationError())
    }

    private func failScan(_ error: Error) {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        manager?.stopScan()
        guard let continuation = scanContinuation else { return }
        scanContinuation = nil
        continuation.resume(throwing: error)
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "蓝牙可用。"
        case .poweredOff: "蓝牙已关闭。"
        case .unauthorized: "蓝牙权限未授予。"
        case .unsupported: "这台设备不支持所需的蓝牙能力。"
        case .resetting: "蓝牙正在重置，请稍后重试。"
        case .unknown: "蓝牙状态尚未确定。"
        @unknown default: "蓝牙状态未知。"
        }
    }
}

nonisolated struct FamiliarBluetoothScanTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let serviceUUIDs: [String]
        let durationSeconds: Double?
    }

    let service: any FamiliarBluetoothServicing
    let manifest = FamiliarToolManifest(
        name: "bluetooth_scan",
        title: "扫描蓝牙设备",
        description: "经明确授权后，在前台按 1 到 8 个指定 BLE Service UUID 扫描 2 到 10 秒。不会连接设备、读取特征值或后台扫描。",
        parameters: .object(
            [
                "serviceUUIDs": .stringArray(
                    "必须显式指定的 BLE Service UUID 列表；不支持无过滤的全量扫描。",
                    itemDescription: "BLE Service UUID，例如 180D 或完整的 128 位 UUID。",
                    minItems: FamiliarToolDefaults.BluetoothScan.minimumServiceUUIDs,
                    maxItems: FamiliarToolDefaults.BluetoothScan.maximumServiceUUIDs
                ),
                "durationSeconds": .number(
                    "前台扫描时长（秒）。",
                    minimum: FamiliarToolDefaults.BluetoothScan.minimumDuration,
                    maximum: FamiliarToolDefaults.BluetoothScan.maximumDuration,
                    defaultValue: FamiliarToolDefaults.BluetoothScan.duration
                )
            ],
            required: ["serviceUUIDs"]
        ),
        effect: .read,
        risk: .high,
        requirements: [.bluetoothScan],
        dataDomains: ["bluetooth.nearby-devices"],
        privacyLabels: ["nearby-devices", "foreground-only"],
        supportsParallelism: false,
        executionClass: .native,
        maximumExecutionDuration: 20
    )

    /// The scan is bounded by the explicit service UUID list, so the confirmation
    /// card shows exactly which UUIDs and for how long.
    func preflight(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolAuthorizationAssessment {
        try FamiliarBluetoothServices.validate(input.serviceUUIDs)
        let duration = min(
            max(input.durationSeconds ?? FamiliarToolDefaults.BluetoothScan.duration, FamiliarToolDefaults.BluetoothScan.minimumDuration),
            FamiliarToolDefaults.BluetoothScan.maximumDuration
        )
        return .init(
            disposition: .requiresApproval,
            effect: manifest.effect,
            risk: manifest.risk,
            reason: manifest.description,
            fields: [
                .init(id: "serviceUUIDs", label: String(localized: "approval.field.service_uuids", defaultValue: "Service UUIDs"), type: .text, value: input.serviceUUIDs.joined(separator: ", ")),
                .init(id: "duration", label: String(localized: "approval.field.duration", defaultValue: "Duration"), type: .number, value: String(format: "%.0f", duration)),
                .init(id: "scope", label: String(localized: "approval.field.scope", defaultValue: "Scope"), type: .text, value: String(localized: "approval.value.bluetooth_scope", defaultValue: "Foreground discovery only. No connection, no characteristic reads."))
            ],
            consequence: String(localized: "approval.consequence.bluetooth_scan", defaultValue: "Familiar discovers nearby devices advertising these services and reports their names and signal strength. Results may be sent to the selected model provider as a tool result."),
            targetKey: "bluetooth-scan"
        )
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let peripherals = try await service.scan(
            serviceUUIDs: input.serviceUUIDs,
            duration: input.durationSeconds ?? FamiliarToolDefaults.BluetoothScan.duration
        )
        let records = peripherals.map { peripheral in
            FamiliarToolPresentationPayload.Record(id: peripheral.id, fields: [
                .init(name: "name", value: peripheral.name ?? "Unknown"),
                .init(name: "rssi", value: String(peripheral.rssi)),
                .init(name: "serviceUUIDs", value: peripheral.advertisedServiceUUIDs.joined(separator: ", ")),
                .init(name: "connectable", value: peripheral.connectable.map(String.init) ?? "unknown")
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: peripherals,
            presentation: .recordCollection(.init(
                summary: "CoreBluetooth 扫描到 \(peripherals.count) 个匹配设备。",
                recordType: "bluetoothPeripheral",
                records: records
            ))
        )))
    }
}

// MARK: - UserNotifications

nonisolated struct FamiliarScheduledNotification: Codable, Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireAtISO8601: String
}

nonisolated struct FamiliarScheduleNotificationTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let title: String
        let body: String
        let fireAtISO8601: String
    }

    private struct UndoOutput: Encodable { let removed: Bool; let identifier: String }

    let manifest = FamiliarToolManifest(
        name: "notification_schedule",
        title: "安排本地通知",
        description: "经确认后使用 UserNotifications 安排一条本地通知。适合普通通知；需要持续响铃的闹钟应使用 AlarmKit。",
        parameters: .init(type: .object, properties: [
            "title": .init(type: .string, description: "通知标题"),
            "body": .init(type: .string, description: "通知正文"),
            "fireAtISO8601": .init(type: .string, description: "带时区的 ISO8601 触发时间，必须晚于当前时间")
        ], required: ["title", "body", "fireAtISO8601"]),
        effect: .reversibleWrite,
        risk: .sensitive,
        requirements: [.userNotifications],
        dataDomains: ["notifications.pending"],
        privacyLabels: ["notification-content"],
        supportsIdempotency: true,
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty, title.count <= 120, body.count <= 1_000 else {
            throw FamiliarAppleDeviceToolError.invalidNotification
        }
        // Uses the shared parser so a timestamp with fractional seconds is accepted
        // here exactly as it is by the EventKit tools.
        let fireAt = try FamiliarISO8601.date(input.fireAtISO8601)
        guard fireAt > Date() else { throw FamiliarAppleDeviceToolError.invalidFutureDate }
        let identifier = "familiar.agent.\(context.runID).\(context.toolCallID)"
        return .action(.init(
            title: manifest.title,
            fields: [
                .init(id: "title", label: "Title", type: .text, value: title),
                .init(id: "body", label: "Body", type: .text, value: body),
                .init(id: "fireAt", label: "Fire At", type: .date, value: fireAt.ISO8601Format())
            ],
            target: identifier,
            targetKey: identifier,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "系统会在指定时间显示并可能播放这条本地通知。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            commit: {
                let scheduled = try await FamiliarNotificationService.scheduleAgentNotification(
                    identifier: identifier,
                    title: title,
                    body: body,
                    fireAt: fireAt
                )
                return FamiliarCommittedAction(
                    result: .init(envelope: try FamiliarToolResultEnvelope(
                        model: scheduled,
                        presentation: .mutationReceipt(.init(
                            summary: "已安排本地通知。",
                            operation: "notificationSchedule",
                            targetIdentifier: identifier,
                            succeeded: true,
                            undoAvailable: true
                        ))
                    )),
                    undo: {
                        await FamiliarNotificationService.removeAgentNotification(identifier: identifier)
                        return .init(envelope: try FamiliarToolResultEnvelope(
                            model: UndoOutput(removed: true, identifier: identifier),
                            presentation: .mutationReceipt(.init(
                                summary: "已移除待发送通知。",
                                operation: "notificationRemove",
                                targetIdentifier: identifier,
                                succeeded: true,
                                undoAvailable: false
                            ))
                        ))
                    }
                )
            }
        ))
    }
}

nonisolated enum FamiliarAppleDeviceToolError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case requestInProgress
    case bluetoothServicesRequired
    case invalidBluetoothServiceUUID
    case invalidNotification
    case invalidFutureDate

    var code: String {
        switch self {
        case .requestInProgress: "capability_request_in_progress"
        case .bluetoothServicesRequired: "bluetooth_service_uuids_required"
        case .invalidBluetoothServiceUUID: "invalid_bluetooth_service_uuid"
        case .invalidNotification: "invalid_notification"
        case .invalidFutureDate: "invalid_future_date"
        }
    }

    var isRetryable: Bool {
        switch self {
        // A concurrent request can finish, so the same call may succeed later.
        case .requestInProgress: true
        case .bluetoothServicesRequired, .invalidBluetoothServiceUUID, .invalidNotification, .invalidFutureDate: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .requestInProgress: "已有一个相同的系统能力请求正在进行。"
        case .bluetoothServicesRequired: "蓝牙扫描必须指定 1 到 8 个 Service UUID。"
        case .invalidBluetoothServiceUUID: "Service UUID 必须是 4 位或 8 位十六进制值，或者完整的 128 位 UUID。"
        case .invalidNotification: "通知标题或正文为空或过长。"
        case .invalidFutureDate: "触发时间必须是有效且晚于当前时间的 ISO8601 日期。"
        }
    }
}
