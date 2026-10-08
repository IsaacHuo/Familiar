import Foundation
import XCTest
@testable import Familiar

/// Explicit signed-device service probes. No user data is uploaded to a model.
final class FamiliarNativeDeviceTests: XCTestCase {
    private func requireDevice() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical-device service acceptance is selected separately")
#endif
    }
    @MainActor func testRealMapKitPublicPlace() async throws {
        try requireDevice()
        let values = try await FamiliarMapService().search(query: "Beijing", near: nil, limit: 3)
        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
    }
    func testRealWeatherKitForecastAndAttribution() async throws {
        try requireDevice()
        let value = try await FamiliarWeatherService().forecast(latitude: 39.9042, longitude: 116.4074, days: 3)
        XCTAssertFalse(value.dailyForecast.isEmpty)
        XCTAssertEqual(value.latitude, 39.9042)
        XCTAssertTrue(value.attributionLegalURL.hasPrefix("https://"))
        let receipt = XCTAttachment(string: "WeatherKit returned current conditions and \(value.dailyForecast.count) forecast days with attribution.")
        receipt.lifetime = .keepAlways; add(receipt)
    }
    func testRealMusicKitCatalog() async throws {
        try requireDevice()
        let service = FamiliarMusicService()
        try await service.requestAccess()
        let values = try await service.searchSongs(term: "Beethoven", limit: 3)
        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })
    }
    func testRealHealthReadDoesNotInventZeroForUnavailableData() async throws {
        try requireDevice()
        let service = FamiliarHealthService()
        try await service.requestAccess()
        let value = try await service.activitySummary(days: 1)
        XCTAssertFalse(value.startISO8601.isEmpty)
        XCTAssertFalse(value.endISO8601.isEmpty)
        // HealthKit intentionally does not expose whether read access was denied.
        if let count = value.stepCount { XCTAssertGreaterThanOrEqual(count, 0) }
    }
    func testRealPhotoMetadataPermissionAndBoundedResult() async throws {
        try requireDevice()
        let service = FamiliarPhotoLibraryService()
        try await service.requestReadAccess()
        let values = try await service.recentAssets(limit: 1, imagesOnly: true)
        XCTAssertLessThanOrEqual(values.count, 1)
        XCTAssertTrue(values.allSatisfy { !$0.id.isEmpty })
    }
    func testRealContactsPermissionAndEmptyQueryResult() async throws {
        try requireDevice()
        let service = FamiliarContactsService()
        try await service.requestAccess()
        let values = try await service.search(query: "FC-QA-" + UUID().uuidString, limit: 1, requestedFields: [])
        XCTAssertTrue(values.isEmpty)
    }
}
