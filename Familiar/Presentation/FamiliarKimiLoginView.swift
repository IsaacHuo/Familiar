import SwiftUI

struct FamiliarKimiLoginView: View {
    @Environment(\.dismiss) private var dismiss
    let instanceID: String
    @State private var authorization: FamiliarKimiDeviceFlow.DeviceAuthorization?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let authorization {
                    Text(String(localized: "oauth.device.instructions")).multilineTextAlignment(.center)
                    Text(authorization.userCode).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
                    if let url = URL(string: authorization.openURL), url.scheme == "https" {
                        Link(String(localized: "oauth.open"), destination: url).buttonStyle(.borderedProminent)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                else { ProgressView(String(localized: "oauth.waiting")) }
            }
            .padding(24)
            .navigationTitle("Kimi Code")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } } }
            .task {
                do {
                    let code = try await FamiliarKimiOAuth.shared.begin()
                    authorization = code
                    try await FamiliarKimiOAuth.shared.finish(code, instanceID: instanceID)
                    dismiss()
                } catch is CancellationError { }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
