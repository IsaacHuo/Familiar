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
}
