import SwiftData
import SwiftUI

@main
struct FamiliarApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                FamiliarConversation.self,
                FamiliarMessage.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Familiar 本地会话数据库初始化失败：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            FamiliarChatView()
                .tint(FamiliarTheme.accent)
        }
        .modelContainer(modelContainer)
    }
}
