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


struct FamiliarAboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: FamiliarSpacing.small) {
                    appIconView
                    Text(String(localized: "app.name")).font(.title2.bold())
                    Text(version).font(FamiliarTypography.secondary).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, FamiliarSpacing.medium)
            }

            Section {
                VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                    Label(String(localized: "settings.about.development.title", defaultValue: "Under Development"), systemImage: "hammer")
                        .font(FamiliarTypography.sectionTitle)
                    Text(String(localized: "settings.about.development.body", defaultValue: "Familiar is still under development: features are incomplete and errors still happen. Feedback and code contributions are welcome. If something feels rough, we will ship fixes as fast as we can."))
                        .font(FamiliarTypography.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, FamiliarSpacing.xSmall)
            }

            Section {
                Link(String(localized: "settings.about.privacy", defaultValue: "Privacy Policy"), destination: URL(string: "https://isaachuo.github.io/familiar/privacy/")!)
                Link(String(localized: "settings.about.support", defaultValue: "Support"), destination: URL(string: "https://isaachuo.github.io/familiar/support/")!)
                Link(String(localized: "settings.about.feedback", defaultValue: "Report an Issue"), destination: URL(string: "https://github.com/IsaacHuo/familiar/issues")!)
                Link(String(localized: "settings.about.source", defaultValue: "Source Code"), destination: URL(string: "https://github.com/IsaacHuo/Familiar")!)
            }

            Section {
                NavigationLink(String(localized: "settings.about.notices", defaultValue: "Third-Party Notices")) {
                    ScrollView {
                        Text(thirdPartyNotices)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(String(localized: "settings.about.notices", defaultValue: "Third-Party Notices"))
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.about", defaultValue: "About Familiar"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var appIconView: some View {
        if let appIcon {
            Image(uiImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: 72, height: 72)
                .background(FamiliarTheme.brandGlow, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        }
    }

    private var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String]
        else { return UIImage(named: "AppIcon") }

        for filename in files.reversed() {
            if let image = UIImage(named: filename) { return image }
            let resource = filename as NSString
            if let path = Bundle.main.path(
                forResource: resource.deletingPathExtension,
                ofType: resource.pathExtension.isEmpty ? "png" : resource.pathExtension
            ), let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return UIImage(named: "AppIcon")
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "settings.about.version", defaultValue: "Version %@ (%@)"), version, build)
    }

    private var thirdPartyNotices: String {
        let names = ["ThirdPartyNotices", "OpenMinisNotices", "ThirdPartyNotices-iSH", "AnyDocRustDependencies", "GPL-3.0", "ISH_LICENSE_IOS", "ISHSourceOffer"]
        let values = names.compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return values.isEmpty
            ? String(localized: "settings.about.notices.unavailable", defaultValue: "Notices are unavailable.")
            : values.joined(separator: "\n\n\n")
    }
}
