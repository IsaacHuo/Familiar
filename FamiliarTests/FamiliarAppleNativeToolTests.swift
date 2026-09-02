import Foundation
import Testing
@testable import Familiar

// MARK: - Fakes

@MainActor
private final class FamiliarMapServiceFixture: FamiliarMapServicing {
    private(set) var requestedLimits: [Int] = []
    private(set) var requestedCenters: [FamiliarLocationSnapshot?] = []

    func search(query: String, near: FamiliarLocationSnapshot?, limit: Int) async throws -> [FamiliarMapPlace] {
        requestedLimits.append(limit)
        requestedCenters.append(near)
        return [FamiliarMapPlace(
            id: "fixture-place",
            name: query,
            address: "Fixture Street 1",
            latitude: 39.9042,
            longitude: 116.4074,
            phoneNumber: nil,
            url: nil
        )]
    }
}

private actor FamiliarWeatherServiceFixture: FamiliarWeatherServicing {
    private(set) var forecastDays: [Int] = []
    private(set) var historyRanges: [(start: Date, end: Date)] = []

    func forecast(latitude: Double, longitude: Double, days: Int) -> FamiliarWeatherSnapshot {
        forecastDays.append(days)
        return FamiliarWeatherSnapshot(
            latitude: latitude,
            longitude: longitude,
            retrievedAtISO8601: "2026-09-02T00:00:00.000Z",
            currentTemperatureCelsius: 24,
            currentApparentTemperatureCelsius: 25,
            currentCondition: "clear",
            currentHumidity: 0.4,
            dailyForecast: [],
            attributionServiceName: "Apple Weather",
            attributionLegalURL: "https://weatherkit.apple.com/legal-attribution.html"
        )
    }

    func history(latitude: Double, longitude: Double, start: Date, end: Date) -> FamiliarWeatherHistory {
        historyRanges.append((start, end))
        return FamiliarWeatherHistory(
            latitude: latitude,
            longitude: longitude,
            startISO8601: FamiliarISO8601.string(start),
            endISO8601: FamiliarISO8601.string(end),
            days: [],
            attributionServiceName: "Apple Weather",
            attributionLegalURL: "https://weatherkit.apple.com/legal-attribution.html"
        )
    }
}

private actor FamiliarHealthServiceFixture: FamiliarHealthServicing {
    private(set) var requestedDays: [Int] = []

    func availability() -> FamiliarCapabilityAvailability { .available }
    func requestAccess() {}

    func activitySummary(days: Int) -> FamiliarHealthActivitySummary {
        requestedDays.append(days)
        return FamiliarHealthActivitySummary(
            startISO8601: "2026-08-26T00:00:00.000Z",
            endISO8601: "2026-09-02T00:00:00.000Z",
            stepCount: nil,
            activeEnergyKilocalories: 420,
            walkingRunningDistanceMeters: nil,
            authorizationDoesNotRevealReadDenials: true
        )
    }
}

private actor FamiliarMusicServiceFixture: FamiliarMusicServicing {
    private(set) var requestedLimits: [Int] = []

    func availability() -> FamiliarCapabilityAvailability { .available }
    func requestAccess() {}

    func searchSongs(term: String, limit: Int) -> [FamiliarMusicSong] {
        requestedLimits.append(limit)
        return [FamiliarMusicSong(
            id: "fixture-song",
            title: term,
            artistName: "Fixture Artist",
            albumTitle: nil,
            durationSeconds: nil,
            url: nil
        )]
    }
}

@MainActor
private final class FamiliarBluetoothServiceFixture: FamiliarBluetoothServicing {
    private(set) var requestedDurations: [TimeInterval] = []

    func availability() async -> FamiliarCapabilityAvailability { .available }
    func requestAccess() async throws {}

    func scan(serviceUUIDs: [String], duration: TimeInterval) async throws -> [FamiliarBluetoothPeripheral] {
        guard serviceUUIDs.count >= FamiliarToolDefaults.BluetoothScan.minimumServiceUUIDs,
              serviceUUIDs.count <= FamiliarToolDefaults.BluetoothScan.maximumServiceUUIDs
        else { throw FamiliarAppleDeviceToolError.bluetoothServicesRequired }
        requestedDurations.append(duration)
        return [FamiliarBluetoothPeripheral(
            id: "fixture-peripheral",
            name: "Fixture",
            rssi: -50,
            advertisedServiceUUIDs: serviceUUIDs,
            connectable: true
        )]
    }
}

private actor FamiliarPhotoReadingFixture: FamiliarPhotoLibraryReading {
    private(set) var requestedLimits: [Int] = []
    private(set) var requestedImagesOnly: [Bool] = []

    func readAvailability() -> FamiliarCapabilityAvailability { .available }
    func requestReadAccess() {}

    func recentAssets(limit: Int, imagesOnly: Bool) -> [FamiliarPhotoAssetMetadata] {
        requestedLimits.append(limit)
        requestedImagesOnly.append(imagesOnly)
        return []
    }
}

private struct FamiliarNaturalLanguageFixture: FamiliarNaturalLanguageServicing {
    func analyze(_ text: String) throws -> FamiliarNaturalLanguageAnalysis {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FamiliarAppleNativeToolError.emptyQuery
        }
        return FamiliarNaturalLanguageAnalysis(
            dominantLanguage: "zh-Hans",
            languageHypotheses: ["zh-Hans": 1],
            sentimentScore: 0,
            people: [],
            places: [],
            organizations: []
        )
    }
}

private actor FamiliarAlarmServiceFixture: FamiliarAlarmServicing {
    private(set) var scheduled: [UUID] = []
    private(set) var cancelled: [UUID] = []
    private var existing: [FamiliarScheduledAlarm]

    init(existing: [FamiliarScheduledAlarm] = []) { self.existing = existing }

    func availability() -> FamiliarCapabilityAvailability { .available }
    func requestAccess() {}

    func schedule(id: UUID, label: String, fireAt: Date) -> FamiliarScheduledAlarm {
        scheduled.append(id)
        let alarm = FamiliarScheduledAlarm(
            id: id.uuidString,
            label: label,
            fireAtISO8601: FamiliarISO8601.string(fireAt),
            state: "scheduled"
        )
        existing.append(alarm)
        return alarm
    }

    func cancel(id: UUID) {
        cancelled.append(id)
        existing.removeAll { $0.id == id.uuidString }
    }

    func alarms() -> [FamiliarScheduledAlarm] { existing }
}

// MARK: - Tests

@Suite("Apple native tool contracts")
struct FamiliarAppleNativeToolTests {
    private func context() -> FamiliarToolContext {
        .init(workspaceID: .conversation(UUID()))
    }

    private func structuredCode(_ error: any Error) -> String? {
        (error as? any FamiliarStructuredToolError)?.code
    }

    // MARK: MapKit

    @Test("Map search applies the shared default and rejects a half-specified center")
    @MainActor
    func mapSearchBoundaries() async throws {
        let service = FamiliarMapServiceFixture()
        let tool = FamiliarMapSearchTool(service: service)

        _ = try await tool.execute(
            .init(query: "故宫", limit: nil, nearLatitude: nil, nearLongitude: nil),
            context: context()
        )
        // The schema advertises this default, so the Swift side must apply the same one.
        #expect(service.requestedLimits == [FamiliarToolDefaults.MapSearch.limit])
        #expect(service.requestedCenters == [nil])

        // A latitude without a longitude is ambiguous and must fail rather than be
        // silently dropped.
        await #expect(throws: FamiliarAppleNativeToolError.self) {
            _ = try await tool.execute(
                .init(query: "故宫", limit: nil, nearLatitude: 39.9, nearLongitude: nil),
                context: context()
            )
        }

        do {
            _ = try await tool.execute(
                .init(query: "故宫", limit: nil, nearLatitude: 200, nearLongitude: 116),
                context: context()
            )
            Issue.record("Expected an out-of-range coordinate to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_coordinate")
            #expect((error as? any FamiliarStructuredToolError)?.isRetryable == false)
        }
    }

    // MARK: WeatherKit

    @Test("Weather forecast applies the advertised default day count")
    func weatherForecastDefault() async throws {
        let service = FamiliarWeatherServiceFixture()
        let tool = FamiliarWeatherForecastTool(service: service)
        _ = try await tool.execute(.init(latitude: 39.9, longitude: 116.4, days: nil), context: context())
        #expect(await service.forecastDays == [FamiliarToolDefaults.WeatherForecast.days])
    }

    @Test("Weather history forwards an exclusive end bound to the service")
    func weatherHistoryRange() async throws {
        let service = FamiliarWeatherServiceFixture()
        let tool = FamiliarWeatherHistoryTool(service: service)
        _ = try await tool.execute(
            .init(
                latitude: 39.9042,
                longitude: 116.4074,
                startISO8601: "2026-08-20T00:00:00Z",
                endISO8601: "2026-08-21T00:00:00Z"
            ),
            context: context()
        )
        let ranges = await service.historyRanges
        #expect(ranges.count == 1)
        #expect(ranges[0].end.timeIntervalSince(ranges[0].start) == 86_400)
    }

    @Test("Weather history rejects an inverted range before reaching WeatherKit")
    func weatherHistoryInvertedRange() async throws {
        let tool = FamiliarWeatherHistoryTool(service: FamiliarWeatherServiceFixture())
        do {
            _ = try await tool.execute(
                .init(
                    latitude: 39.9,
                    longitude: 116.4,
                    startISO8601: "2026-08-21T00:00:00Z",
                    endISO8601: "2026-08-20T00:00:00Z"
                ),
                context: context()
            )
            Issue.record("Expected an inverted range to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_range")
        }
    }

    /// These bounds are enforced inside `FamiliarWeatherService` before any network
    /// call, so the real service can be exercised deterministically.
    @Test("Real weather service enforces WeatherKit's documented history limits")
    func weatherHistoryPlatformLimits() async throws {
        let service = FamiliarWeatherService()
        let earliest = FamiliarToolDefaults.WeatherHistory.earliestDate

        do {
            _ = try await service.history(
                latitude: 39.9,
                longitude: 116.4,
                start: earliest.addingTimeInterval(-86_400),
                end: earliest
            )
            Issue.record("Expected a pre-coverage start date to fail")
        } catch {
            #expect(structuredCode(error) == "weather_history_before_coverage")
        }

        do {
            let start = earliest.addingTimeInterval(86_400)
            _ = try await service.history(
                latitude: 39.9,
                longitude: 116.4,
                start: start,
                end: start.addingTimeInterval(Double(FamiliarToolDefaults.WeatherHistory.maximumDays + 2) * 86_400)
            )
            Issue.record("Expected an oversized range to fail instead of being truncated")
        } catch {
            #expect(structuredCode(error) == "weather_history_range_too_long")
            // Truncating would let the model believe it received days it never got.
            #expect((error as? any FamiliarStructuredToolError)?.isRetryable == false)
        }
    }

    // MARK: HealthKit

    @Test("Health preflight states the real window and never reports a value as zero")
    func healthPreflightScope() async throws {
        let service = FamiliarHealthServiceFixture()
        let tool = FamiliarHealthActivitySummaryTool(service: service)

        let assessment = try await tool.preflight(.init(days: 3), context: context())
        #expect(assessment.disposition == .requiresApproval)
        #expect(assessment.risk == .high)
        #expect(assessment.targetKey == "health-activity")
        #expect(!assessment.fields.isEmpty)
        #expect(assessment.fields.contains { $0.value.contains("3") })
        #expect(assessment.fields.contains { $0.value.contains("stepCount") })
        #expect(!assessment.consequence.isEmpty)

        // A day count beyond the platform bound is clamped, not rejected, and the
        // approval card must show the clamped value rather than the request.
        let clamped = try await tool.preflight(
            .init(days: FamiliarToolDefaults.HealthActivity.maximumDays + 40),
            context: context()
        )
        #expect(clamped.fields.contains { $0.value.contains(String(FamiliarToolDefaults.HealthActivity.maximumDays)) })

        let outcome = try await tool.execute(.init(days: nil), context: context())
        guard case .result(let result) = outcome else { Issue.record("Expected a result"); return }
        #expect(await service.requestedDays == [FamiliarToolDefaults.HealthActivity.days])
        // HealthKit never reveals read denials, so an unavailable metric must not be
        // reported as a real zero. A nil optional is omitted from the encoded model
        // JSON rather than encoded as null.
        #expect(!result.modelContent.contains("\"stepCount\":0"))
        #expect(result.modelContent.contains("activeEnergyKilocalories"))
        #expect(result.summary.contains("未授权") || result.summary.contains("空值"))
        guard case .recordCollection(let records) = result.envelope.presentation.content else {
            Issue.record("Expected a record collection")
            return
        }
        #expect(records.records.first?.fields.contains { $0.value == "unavailable" } == true)
    }

    // MARK: PhotoKit

    @Test("Photo metadata preflight states the item count and location exposure")
    func photoPreflightScope() async throws {
        let photos = FamiliarPhotoReadingFixture()
        let tool = FamiliarPhotosRecentMetadataTool(photos: photos)

        let assessment = try await tool.preflight(.init(limit: 5, imagesOnly: false), context: context())
        #expect(assessment.disposition == .requiresApproval)
        #expect(assessment.targetKey == "photos-recent-metadata")
        #expect(assessment.fields.contains { $0.value == "5" })
        #expect(assessment.consequence.contains("location") || assessment.consequence.contains("位置"))

        _ = try await tool.execute(.init(limit: nil, imagesOnly: nil), context: context())
        #expect(await photos.requestedLimits == [FamiliarToolDefaults.PhotoMetadata.limit])
        #expect(await photos.requestedImagesOnly == [FamiliarToolDefaults.PhotoMetadata.imagesOnly])
    }

    // MARK: MusicKit

    @Test("Music catalog search applies the advertised default limit")
    func musicSearchDefault() async throws {
        let service = FamiliarMusicServiceFixture()
        let tool = FamiliarMusicCatalogSearchTool(service: service)
        _ = try await tool.execute(.init(query: "fixture", limit: nil), context: context())
        #expect(await service.requestedLimits == [FamiliarToolDefaults.MusicSearch.limit])
    }

    // MARK: CoreBluetooth

    @Test("Bluetooth scan requires explicit service UUIDs and surfaces them for approval")
    @MainActor
    func bluetoothScanScope() async throws {
        let service = FamiliarBluetoothServiceFixture()
        let tool = FamiliarBluetoothScanTool(service: service)

        let assessment = try await tool.preflight(
            .init(serviceUUIDs: ["180D", "180F"], durationSeconds: nil),
            context: context()
        )
        #expect(assessment.targetKey == "bluetooth-scan")
        #expect(assessment.fields.contains { $0.value.contains("180D") && $0.value.contains("180F") })
        #expect(assessment.fields.contains {
            $0.value == String(format: "%.0f", FamiliarToolDefaults.BluetoothScan.duration)
        })

        // An unfiltered scan is not offered at all.
        do {
            _ = try await tool.execute(.init(serviceUUIDs: [], durationSeconds: nil), context: context())
            Issue.record("Expected an empty UUID list to fail")
        } catch {
            #expect(structuredCode(error) == "bluetooth_service_uuids_required")
        }

        _ = try await tool.execute(.init(serviceUUIDs: ["180D"], durationSeconds: nil), context: context())
        #expect(service.requestedDurations == [FamiliarToolDefaults.BluetoothScan.duration])
    }

    // MARK: NaturalLanguage

    @Test("Natural language analysis rejects empty input on device")
    func naturalLanguageEmptyInput() async throws {
        let tool = FamiliarNaturalLanguageAnalyzeTool(service: FamiliarNaturalLanguageFixture())
        do {
            _ = try await tool.execute(.init(text: "   \n "), context: context())
            Issue.record("Expected empty text to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_query")
        }
    }

    // MARK: UserNotifications

    @Test("Notification scheduling accepts fractional-second timestamps like EventKit does")
    func notificationAcceptsFractionalSeconds() async throws {
        let tool = FamiliarScheduleNotificationTool()
        let fireAt = FamiliarISO8601.string(Date().addingTimeInterval(3_600))
        // Previously this tool used a bare ISO8601DateFormatter and rejected the exact
        // timestamp format the EventKit tools emit.
        let outcome = try await tool.execute(
            .init(title: "Fixture", body: "Body", fireAtISO8601: fireAt),
            context: context()
        )
        guard case .action(let proposal) = outcome else { Issue.record("Expected an action proposal"); return }
        #expect(proposal.effect == .reversibleWrite)
        #expect(proposal.undoPolicy == .currentSession)

        do {
            _ = try await tool.execute(
                .init(title: "Fixture", body: "Body", fireAtISO8601: "not-a-date"),
                context: context()
            )
            Issue.record("Expected an invalid timestamp to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_iso8601")
        }
    }

    // MARK: AlarmKit

    @Test("Alarm scheduling commits only after approval and offers a durable undo")
    func alarmScheduleCommitBoundary() async throws {
        let service = FamiliarAlarmServiceFixture()
        let tool = FamiliarAlarmScheduleTool(service: service)
        let fireAt = Date().addingTimeInterval(7_200)

        let outcome = try await tool.execute(
            .init(label: "起床", fireAtISO8601: FamiliarISO8601.string(fireAt)),
            context: context()
        )
        guard case .action(let proposal) = outcome else { Issue.record("Expected an action proposal"); return }
        #expect(await service.scheduled.isEmpty)
        // An alarm fires later, very likely after a relaunch, so a session-scoped undo
        // would be a promise the app cannot keep.
        #expect(proposal.undoPolicy == .durable)
        // A fresh alarm identity per call means a reusable authorization could never
        // match; every alarm is confirmed exactly once.
        #expect(proposal.allowedAuthorizationDurations == [.once])
        #expect(proposal.fields.contains { $0.value == "起床" })

        let committed = try await proposal.commit()
        let scheduledIDs = await service.scheduled
        #expect(scheduledIDs.count == 1)
        // The identity must reach the durable undo recorder.
        #expect(committed.result.artifactIdentifier == scheduledIDs[0].uuidString)

        let undo = try #require(committed.undo)
        _ = try await undo()
        #expect(await service.cancelled == scheduledIDs)
    }

    @Test("Alarm scheduling rejects an empty label and a past time")
    func alarmScheduleValidation() async throws {
        let tool = FamiliarAlarmScheduleTool(service: FamiliarAlarmServiceFixture())
        let future = FamiliarISO8601.string(Date().addingTimeInterval(600))

        do {
            _ = try await tool.execute(.init(label: "  ", fireAtISO8601: future), context: context())
            Issue.record("Expected an empty label to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_alarm_label")
        }

        do {
            _ = try await tool.execute(
                .init(label: "起床", fireAtISO8601: FamiliarISO8601.string(Date().addingTimeInterval(-600))),
                context: context()
            )
            Issue.record("Expected a past time to fail")
        } catch {
            #expect(structuredCode(error) == "invalid_future_date")
        }
    }

    @Test("Alarm cancellation only targets alarms Familiar itself scheduled")
    func alarmCancelOwnership() async throws {
        let known = UUID()
        let service = FamiliarAlarmServiceFixture(existing: [
            .init(id: known.uuidString, label: "起床", fireAtISO8601: nil, state: "scheduled")
        ])
        let tool = FamiliarAlarmCancelTool(service: service)

        // A hallucinated identifier fails before any confirmation card appears.
        do {
            _ = try await tool.execute(.init(alarmID: UUID().uuidString), context: context())
            Issue.record("Expected an unknown alarm to fail")
        } catch {
            #expect(structuredCode(error) == "alarm_not_found")
        }
        #expect(await service.cancelled.isEmpty)

        let outcome = try await tool.execute(.init(alarmID: known.uuidString), context: context())
        guard case .action(let proposal) = outcome else { Issue.record("Expected an action proposal"); return }
        #expect(proposal.effect == .destructiveWrite)
        #expect(proposal.undoPolicy == .unavailable)
        _ = try await proposal.commit()
        #expect(await service.cancelled == [known])
    }

    @Test("Alarm tools declare the usage description AlarmKit requires to function")
    func alarmRequirementDeclaration() {
        // AlarmKit refuses to schedule anything when NSAlarmKitUsageDescription is
        // missing or empty, so this is a functional dependency, not a courtesy string.
        #expect(FamiliarCapabilityRequirement.alarmKit.usageDescriptionKey == "NSAlarmKitUsageDescription")
        #expect(FamiliarCapabilityRequirement.alarmKit.entitlementKey == nil)
        for tool in [
            FamiliarAlarmScheduleTool(service: FamiliarAlarmServiceFixture()).manifest,
            FamiliarAlarmCancelTool(service: FamiliarAlarmServiceFixture()).manifest,
            FamiliarAlarmListTool(service: FamiliarAlarmServiceFixture()).manifest
        ] {
            #expect(tool.requirements == [.alarmKit])
            #expect(tool.executionClass == .native)
        }
    }
}
