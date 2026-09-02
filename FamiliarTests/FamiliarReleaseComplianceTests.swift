import Foundation
import Testing
@testable import Familiar

@Suite("Release compliance contracts")
struct FamiliarReleaseComplianceTests {
    @Test("Every distributed target has a valid non-tracking privacy manifest")
    func privacyManifests() throws {
        for relativePath in [
            "Familiar/PrivacyInfo.xcprivacy",
            "FamiliarShareExtension/PrivacyInfo.xcprivacy",
            "FamiliarWidgets/PrivacyInfo.xcprivacy"
        ] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
            let value = try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
            #expect(value["NSPrivacyTracking"] as? Bool == false)
            #expect(value["NSPrivacyTrackingDomains"] as? [String] == [])
            #expect(value["NSPrivacyAccessedAPITypes"] is [Any])
            #expect(value["NSPrivacyCollectedDataTypes"] is [Any])
        }

        let appData = try Data(contentsOf: repositoryRoot.appendingPathComponent("Familiar/PrivacyInfo.xcprivacy"))
        let app = try #require(PropertyListSerialization.propertyList(from: appData, options: [], format: nil) as? [String: Any])
        let accessed = try #require(app["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: accessed.compactMap { value -> (String, [String])? in
            guard let type = value["NSPrivacyAccessedAPIType"] as? String,
                  let values = value["NSPrivacyAccessedAPITypeReasons"] as? [String]
            else { return nil }
            return (type, values)
        })
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
        #expect(Set(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] ?? []) == ["C617.1", "3B52.1"])
    }

    @Test("Every declared capability ships its Info.plist usage description in both languages")
    func capabilityUsageDescriptions() throws {
        let info = try plist("Familiar/Resources/Info.plist")
        let english = try stringsFile("Familiar/Resources/en.lproj/InfoPlist.strings")
        let chinese = try stringsFile("Familiar/Resources/zh-Hans.lproj/InfoPlist.strings")

        for requirement in FamiliarCapabilityRequirement.allCases {
            guard let key = requirement.usageDescriptionKey else { continue }
            let base = info[key] as? String
            #expect(base?.isEmpty == false, "Info.plist is missing \(key) for \(requirement.rawValue)")
            #expect(english[key]?.isEmpty == false, "en.lproj/InfoPlist.strings is missing \(key)")
            #expect(chinese[key]?.isEmpty == false, "zh-Hans.lproj/InfoPlist.strings is missing \(key)")
        }

        // The base development region is zh-Hans, so every localizable usage
        // description must exist in both catalogs or a prompt ships untranslated.
        let localizableKeys = Set(FamiliarCapabilityRequirement.allCases.compactMap(\.usageDescriptionKey))
        #expect(localizableKeys.isSubset(of: Set(english.keys)))
        #expect(Set(english.keys) == Set(chinese.keys))
    }

    @Test("Every declared capability ships its entitlement and privacy data types")
    func capabilityEntitlementsAndPrivacyTypes() throws {
        let entitlements = try plist("Familiar/Familiar.entitlements")
        let privacy = try plist("Familiar/PrivacyInfo.xcprivacy")
        let declared = Set(
            (privacy["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
                .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        )

        for requirement in FamiliarCapabilityRequirement.allCases {
            if let key = requirement.entitlementKey {
                #expect(entitlements[key] as? Bool == true, "Familiar.entitlements is missing \(key) for \(requirement.rawValue)")
            }
            for dataType in requirement.privacyCollectedDataTypes {
                #expect(declared.contains(dataType), "PrivacyInfo.xcprivacy is missing \(dataType) for \(requirement.rawValue)")
            }
        }
    }

    @Test("Registered tools only require capabilities with complete shipping declarations") @MainActor
    func registeredToolCapabilitiesAreDeclared() async throws {
        let manifests = await FamiliarAppDependencies().registry.snapshot()
        let required = Set(manifests.flatMap(\.requirements))
        #expect(!required.isEmpty)

        let info = try plist("Familiar/Resources/Info.plist")
        let entitlements = try plist("Familiar/Familiar.entitlements")

        for requirement in required {
            if let key = requirement.usageDescriptionKey {
                #expect((info[key] as? String)?.isEmpty == false, "\(requirement.rawValue) is used by a registered tool but \(key) is missing")
            }
            if let key = requirement.entitlementKey {
                #expect(entitlements[key] as? Bool == true, "\(requirement.rawValue) is used by a registered tool but \(key) is missing")
            }
        }
    }

    @Test("The iOS target excludes FastVLM and release fixtures")
    func excludedReleaseCode() throws {
        let project = try source("familiar.xcodeproj/project.pbxproj")
        #expect(!project.contains("FastVLMRuntime in Frameworks"))
        #expect(!project.contains("XCLocalSwiftPackageReference \"Vendor/ml-fastvlm\""))
        #expect(project.contains("LocalVision/FamiliarLocalVisionModelManager.swift"))

        let visionProcessor = try source("Familiar/Vision/FamiliarVisionProcessor.swift")
        #expect(!visionProcessor.localizedCaseInsensitiveContains("fastvlm"))

        let rootView = try source("Familiar/Presentation/FamiliarRootView.swift")
        let messageViews = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        #expect(rootView.contains("#if DEBUG"))
        #expect(rootView.contains("ProcessInfo.processInfo.arguments.contains(\"-familiar.visual-fixture\")"))
        #expect(messageViews.contains("#if DEBUG\nstruct FamiliarAssistantTurnVisualFixture"))
    }

    @Test("Shipped notice resources include bundled web and Rust dependencies")
    func thirdPartyNotices() throws {
        let main = try source("Familiar/Resources/ThirdPartyNotices.txt")
        for name in ["AnyDoc 0.1.8", "SwiftSoup 2.13.7", "markdown-it 14.1.0", "KaTeX 0.16.22", "Mermaid", "Highlight.js 11.11.1", "DOMPurify 3.2.6"] {
            #expect(main.contains(name))
        }
        let rust = try source("Familiar/Resources/AnyDocRustDependencies.txt")
        #expect(rust.contains("Generated from Vendor/AnyDocBridgeRust/Cargo.lock"))
        #expect(rust.contains("anydoc 0.1.8"))
        #expect(rust.contains("encoding_rs 0.8.35"))
        #expect(rust.contains("LICENSE AND NOTICE TEXTS"))
    }

    @Test("iSH rootfs installer accepts only the canonical empty tar root entry")
    func rootfsArchiveRootEntryContract() throws {
        let bridge = try source("Vendor/ISHRuntime/Bridge/ISHKernel.m")
        #expect(bridge.contains("relative.length == 0 && type == '5' && size == 0"))
        #expect(bridge.contains("if (!FamiliarISHSafeArchivePath(relative))"))
        #expect(bridge.contains("generic_mkdirat(AT_PWD, \"/workspace\", 0755)"))
        let archiveListing = try source("Scripts/prepare-ish-rootfs.sh")
        #expect(archiveListing.contains("tar -czf \"$OUTPUT_ARCHIVE\" -C \"$FAKEFS_DIRECTORY\" ."))
    }

    @Test("Dynamic AI colors are safe for SwiftUI async rendering")
    func dynamicColorIsolation() throws {
        let theme = try source("Familiar/Support/FamiliarTheme.swift")
        #expect(theme.contains("nonisolated enum FamiliarAISurfaceColor"))
        #expect(theme.contains("private nonisolated extension UIColor"))
        #expect(!theme.contains("@MainActor\nenum FamiliarAISurfaceColor"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(value as? [String: Any])
    }

    /// `.strings` files use the OpenStep property list format.
    private func stringsFile(_ relativePath: String) throws -> [String: String] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(value as? [String: String])
    }
}
