import ImageIO
import PhotosUI
import SwiftUI

nonisolated struct FamiliarLocalProfile: Codable {
    var name = ""
    var bio = ""
    var avatar: Data?

    static func read(_ data: Data) -> Self { (try? JSONDecoder().decode(Self.self, from: data)) ?? .init() }
    var displayName: String { name.isEmpty ? String(localized: "profile.default_name") : name }
}

struct FamiliarLocalProfileSection: View {
    @AppStorage("familiar.local-profile") private var data = Data()
    @Binding var editing: Bool
    let motionAnchor: FamiliarProfileMotionAnchor
    private var profile: FamiliarLocalProfile { .read(data) }
    var body: some View {
        Section {
            Button { editing = true } label: {
                FamiliarProfileSourceView(anchor: motionAnchor)
                    .frame(height: FamiliarProfileHeaderMotion.height(profile))
                    .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(profile.displayName + (profile.bio.isEmpty ? "" : ", " + profile.bio))
            .accessibilityIdentifier("settings.profile")
            .accessibilityHint(String(localized: "profile.edit"))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .sheet(isPresented: $editing) {
            FamiliarLocalProfileEditor(profile: profile) { value in
                data = value
            }
        }
    }
}

private struct FamiliarProfileAvatar: View {
    let profile: FamiliarLocalProfile
    let size: CGFloat
    var body: some View {
        Group {
            if let data = profile.avatar, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(Color.blue.gradient)
                    .overlay { Text(String(profile.displayName.prefix(1))).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.white) }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct FamiliarLocalProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: FamiliarLocalProfile
    let onSave: (Data) -> Void
    var embeddedNavigation = false
    @State private var photo: PhotosPickerItem?
    @State private var loading = false
    @State private var photoGeneration: UUID?
    @State private var errorMessage: String?

    var body: some View {
        let avatarProfile = profile
        let isLoading = loading
        Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        VStack(spacing: 12) {
                            FamiliarProfileAvatar(profile: avatarProfile, size: 112)
                            if isLoading { ProgressView() }
                            else { Text(String(localized: "profile.avatar.change")) }
                        }.frame(maxWidth: .infinity).padding(.vertical)
                    }.buttonStyle(.plain)
                    if profile.avatar != nil {
                        Button(String(localized: "profile.avatar.remove"), role: .destructive) {
                            photo = nil; profile.avatar = nil
                        }
                    }
                }
                Section {
                    TextField(String(localized: "profile.name"), text: $profile.name)
                        .textContentType(.nickname)
                    TextField(String(localized: "profile.bio"), text: $profile.bio, axis: .vertical)
                        .lineLimit(2...4)
                } footer: { Text(String(localized: "profile.local")) }
            }
            .navigationTitle(String(localized: "profile.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embeddedNavigation { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save() }.disabled(loading)
                }
            }
            .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        .modifier(FamiliarProfileNavigation(embedded: embeddedNavigation))
        .task(id: photo) {
            guard let photo else { loading = false; photoGeneration = nil; return }
            let generation = UUID()
            photoGeneration = generation
            loading = true
            defer { if photoGeneration == generation { loading = false } }
            do {
                guard let source = try await photo.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let avatar = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(source as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 512
                          ] as CFDictionary),
                          let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileReadCorruptFile) }
                    return data
                }.value
                try Task.checkCancellation()
                profile.avatar = avatar
            } catch is CancellationError { }
            catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }

    private func save() {
        profile.name = String(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        profile.bio = String(profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        do { onSave(try JSONEncoder().encode(profile)); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct FamiliarLocalProfileDestination: View {
    @AppStorage("familiar.local-profile") private var data = Data()
    var body: some View {
        FamiliarLocalProfileEditor(profile: .read(data), onSave: { data = $0 }, embeddedNavigation: true)
    }
}

private struct FamiliarProfileNavigation: ViewModifier {
    let embedded: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content } else { NavigationStack { content } }
    }
}
