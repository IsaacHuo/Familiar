import CoreBluetooth
import Testing
@testable import Familiar

@MainActor private final class BluetoothCentralProbe: FamiliarBluetoothCentral {
    var state: CBManagerState = .unknown
    var isScanning = false
    var scanCount = 0
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) {
        scanCount += 1
        isScanning = true
    }
    func stopScan() { isScanning = false }
}

@Suite("Bluetooth production service lifecycle", .serialized)
@MainActor struct FamiliarBluetoothLifecycleTests {
    @Test("Malformed service IDs fail before constructing a manager or requesting permission", arguments: ["", "not-a-uuid", "123", "ZZZZ", "ＦＦＦＦ", "00000000-0000-0000-0000-invalid"])
    func malformedServiceID(_ value: String) async throws {
        let central = BluetoothCentralProbe()
        var constructions = 0
        let service = FamiliarBluetoothService(authorization: { .notDetermined }, makeManager: { _ in constructions += 1; return central })
        await #expect(throws: FamiliarAppleDeviceToolError.self) { _ = try await service.scan(serviceUUIDs: [value], duration: 2) }
        #expect(constructions == 0)
        #expect(central.scanCount == 0)
        try FamiliarBluetoothServices.validate(["180D", "12345678", "0000180D-0000-1000-8000-00805F9B34FB"])
    }

    @Test("Previously granted permission waits for the fresh central to become ready")
    func freshAuthorizedCentral() async throws {
        let central = BluetoothCentralProbe()
        let service = FamiliarBluetoothService(authorization: { .allowedAlways }, makeManager: { _ in central })
        let request = Task { try await service.requestAccess() }
        defer { request.cancel() }
        try await Task.sleep(for: .milliseconds(50))
        central.state = .poweredOn
        service.centralStateDidChange()
        try await request.value
        #expect(service.availability() == .available)
        central.state = .poweredOff
        service.centralStateDidChange()
        await #expect(throws: (any Error).self) { try await service.requestAccess() }
        #expect(central.scanCount == 0)
    }

    @Test("Cancelling the permission wait frees it for the next request")
    func cancelledAuthorization() async throws {
        let central = BluetoothCentralProbe()
        let service = FamiliarBluetoothService(authorization: { .allowedAlways }, makeManager: { _ in central })
        let first = Task { try await service.requestAccess() }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        central.state = .poweredOn
        try await service.requestAccess()
        let cancelled = Task { try await service.scan(serviceUUIDs: ["180D"], duration: 2) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(central.scanCount == 0)
    }

    @Test("A cancelled scan's old deadline cannot stop the next scan; power loss stops it")
    func staleDeadline() async throws {
        let central = BluetoothCentralProbe()
        central.state = .poweredOn
        let service = FamiliarBluetoothService(authorization: { .allowedAlways }, makeManager: { _ in central })
        let first = Task { try await service.scan(serviceUUIDs: ["180D"], duration: 2) }
        try await Task.sleep(for: .milliseconds(80))
        #expect(central.isScanning)
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(!central.isScanning)
        let next = Task { try await service.scan(serviceUUIDs: ["180F"], duration: 4) }
        defer { next.cancel() }
        try await Task.sleep(for: .milliseconds(2200))
        #expect(central.scanCount == 2)
        #expect(central.isScanning)
        central.state = .poweredOff
        service.centralStateDidChange()
        await #expect(throws: (any Error).self) { _ = try await next.value }
        #expect(!central.isScanning)
    }
}
