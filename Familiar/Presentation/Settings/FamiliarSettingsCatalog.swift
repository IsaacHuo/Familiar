import SwiftUI

struct FamiliarSettingsEntry: Identifiable {
    var id: FamiliarSettingsRoute { route }
    let route: FamiliarSettingsRoute
    let titleKey: String
    let groupKey: String
    let detailKey: String
    let symbol: String
    let color: Color
    let aliases: String
    var title: String { String(localized: String.LocalizationValue(titleKey)) }
    var group: String { String(localized: String.LocalizationValue(groupKey)) }
    var detail: String { String(localized: String.LocalizationValue(detailKey)) }
    var path: String { String(localized: "drawer.settings") + " › " + group }
    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let searchable = [title, path, detail, aliases].joined(separator: " ")
        return !terms.isEmpty && terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
    }
}

enum FamiliarSettingsCatalog {
    static let groups = ["settings.hub.models", "settings.hub.personalization", "settings.hub.capabilities", "settings.hub.interface", "settings.privacy.title", "settings.hub.support", "settings.developer"]
    static let entries: [FamiliarSettingsEntry] = [
        .init(route: .profile, titleKey: "profile.edit", groupKey: "settings.hub.personalization", detailKey: "profile.local", symbol: "person.crop.circle", color: .blue, aliases: "profile avatar nickname bio photo 资料 头像 昵称 简介"),
        .init(route: .modelService, titleKey: "settings.hub.model_service", groupKey: "settings.hub.models", detailKey: "provider.instances.footer", symbol: "key.horizontal.fill", color: .blue, aliases: "provider model api key endpoint base url 模型 服务商 密钥 验证 登录"),
        .init(route: .modelGroups, titleKey: "group.title", groupKey: "settings.hub.models", detailKey: "group.detail", symbol: "square.stack", color: .blue, aliases: "model group fallback 模型组 备用 故障切换"),
        .init(route: .soul, titleKey: "settings.hub.soul", groupKey: "settings.hub.personalization", detailKey: "settings.hub.soul.detail", symbol: "sparkles", color: .pink, aliases: "personality prompt tone style 人格 提示词 语气 风格"),
        .init(route: .memory, titleKey: "settings.memory.title", groupKey: "settings.hub.personalization", detailKey: "settings.hub.memory.detail", symbol: "brain", color: .pink, aliases: "memory remember preference fact 记忆 偏好 事实 自动记忆"),
        .init(route: .voice, titleKey: "voice.title", groupKey: "settings.hub.personalization", detailKey: "voice.providers", symbol: "waveform", color: .blue, aliases: "voice speech microphone transcription 语音 麦克风 转写 朗读"),
        .init(route: .searchService, titleKey: "settings.search.title", groupKey: "settings.hub.capabilities", detailKey: "settings.search.title", symbol: "magnifyingglass", color: .blue, aliases: "search web tavily duckduckgo bing api key 搜索 联网 密钥"),
        .init(route: .skills, titleKey: "settings.skills.title", groupKey: "settings.hub.capabilities", detailKey: "settings.skills.detail", symbol: "wand.and.stars", color: .purple, aliases: "skills install guidance 技能 安装 指引"),
        .init(route: .mcp, titleKey: "mcp.title", groupKey: "settings.hub.capabilities", detailKey: "mcp.settings.detail", symbol: "wrench.and.screwdriver", color: .blue, aliases: "mcp server remote tools trusted 服务器 远程工具 信任"),
        .init(route: .tools, titleKey: "settings.hub.tools", groupKey: "settings.hub.capabilities", detailKey: "settings.hub.tools.detail", symbol: "puzzlepiece.extension.fill", color: .blue, aliases: "tool capability calendar reminders 工具 能力 日历 提醒"),
        .init(route: .executionBudget, titleKey: "settings.budget.title", groupKey: "settings.hub.capabilities", detailKey: "settings.budget.title", symbol: "gauge.with.needle", color: .purple, aliases: "budget steps iterations timeout duration 预算 步骤 调用 时限"),
        .init(route: .shellRuntime, titleKey: "settings.shell.title", groupKey: "settings.hub.capabilities", detailKey: "settings.shell.detail", symbol: "shippingbox", color: .gray, aliases: "shell alpine ish terminal environment 终端 运行环境 文件生成"),
        .init(route: .pythonPackageSource, titleKey: "settings.python_source.title", groupKey: "settings.hub.capabilities", detailKey: "settings.python_source.title", symbol: "shippingbox.fill", color: .orange, aliases: "python pip mirror package source 清华 镜像 依赖 包源"),
        .init(route: .appearance, titleKey: "settings.hub.appearance", groupKey: "settings.hub.interface", detailKey: "settings.hub.appearance", symbol: "paintbrush.fill", color: .indigo, aliases: "appearance theme dark light 外观 主题 深色 浅色"),
        .init(route: .permissions, titleKey: "settings.hub.permissions", groupKey: "settings.privacy.title", detailKey: "settings.hub.permissions.detail", symbol: "hand.raised.fill", color: .orange, aliases: "permissions system notifications camera photos health 权限 通知 相机 照片 健康"),
        .init(route: .authorizations, titleKey: "settings.hub.authorizations", groupKey: "settings.privacy.title", detailKey: "settings.hub.authorizations.detail", symbol: "checkmark.shield.fill", color: .green, aliases: "authorization approval revoke allow 授权 审批 撤销 允许"),
        .init(route: .appLock, titleKey: "lock.setting", groupKey: "settings.privacy.title", detailKey: "lock.footer", symbol: "lock", color: .blue, aliases: "lock face id touch id privacy 锁定 面容 指纹 隐私"),
        .init(route: .storage, titleKey: "settings.hub.storage", groupKey: "settings.privacy.title", detailKey: "settings.hub.storage.detail", symbol: "internaldrive.fill", color: .blue, aliases: "storage disk files attachments workspace cache 存储 空间 文件 附件 缓存"),
        .init(route: .dataHandling, titleKey: "settings.privacy.data_handling", groupKey: "settings.privacy.title", detailKey: "settings.hub.privacy.detail", symbol: "hand.raised.square.fill", color: .cyan, aliases: "data privacy local cloud 数据 隐私 本机 云端"),
        .init(route: .about, titleKey: "settings.hub.about", groupKey: "settings.hub.support", detailKey: "settings.hub.about", symbol: "info.circle.fill", color: .indigo, aliases: "about version license 关于 版本 许可"),
        .init(route: .runHistory, titleKey: "settings.hub.run_history", groupKey: "settings.developer", detailKey: "settings.hub.run_history.detail", symbol: "clock.arrow.circlepath", color: .gray, aliases: "runs history receipts execution 运行 历史 回执 执行"),
        .init(route: .diagnostics, titleKey: "settings.diagnostics.title", groupKey: "settings.developer", detailKey: "settings.diagnostics.detail", symbol: "stethoscope", color: .teal, aliases: "diagnostics tools environment debug 诊断 调试 环境")
    ]
}

struct FamiliarSettingsCatalogRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: FamiliarSettingsEntry
    let status: String
    var body: some View {
        HStack(spacing: 16) {
            FamiliarSettingsRowIcon(symbol: entry.symbol, color: entry.color)
            Group {
                if typeSize.isAccessibilitySize { stacked }
                else {
                    HStack {
                        Text(entry.title).lineLimit(1).layoutPriority(1)
                        Spacer(minLength: 8)
                        if !status.isEmpty { Text(status).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }.padding(.vertical, 16)
        }.font(FamiliarTypography.body).frame(minHeight: 44)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
            if !status.isEmpty { Text(status).font(.subheadline).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
