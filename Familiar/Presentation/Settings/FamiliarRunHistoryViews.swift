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


struct FamiliarRunHistoryView: View {
    @Query(sort: \FamiliarAgentRun.startedAt, order: .reverse) private var runs: [FamiliarAgentRun]

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.runs.empty.title", defaultValue: "No runs yet"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "settings.runs.empty.detail", defaultValue: "Completed and failed Agent runs will appear here."))
                )
            } else {
                List(runs) { run in
                    NavigationLink {
                        FamiliarRunRecordDetail(run: run)
                    } label: {
                        FamiliarRunRecordRow(run: run)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.run_history", defaultValue: "Run History"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
