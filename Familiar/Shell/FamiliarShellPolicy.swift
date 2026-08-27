import Foundation

nonisolated enum FamiliarShellPolicyDecision: Equatable, Sendable {
    case allow
    case requiresConfirmation(reason: String)
    case deny(reason: String)
}

nonisolated struct FamiliarShellPolicy: Sendable {
    static let maximumCommandCharacters = 32_000

    func evaluate(command: String) -> FamiliarShellPolicyDecision {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= Self.maximumCommandCharacters else {
            return .deny(reason: "命令为空或超过长度限制。")
        }

        if matches(networkPattern, in: normalized) {
            return .deny(reason: "Shell Runtime 第一阶段不允许网络访问。")
        }
        if matches(hostPathPattern, in: normalized) {
            return .deny(reason: "Shell 只能访问当前 Familiar Workspace。")
        }
        if matches(processEscapePattern, in: normalized) {
            return .deny(reason: "不允许后台常驻、挂载、切换根目录或创建异常进程。")
        }
        if matches(policyBypassPattern, in: normalized) {
            return .deny(reason: "不允许通过编码、eval 或动态 Shell 绕过命令策略。")
        }
        if matches(infiniteLoopPattern, in: normalized) {
            return .deny(reason: "检测到无限循环或资源耗尽模式。")
        }
        if matches(destructivePattern, in: normalized) {
            return .requiresConfirmation(reason: "命令可能删除、覆盖或重置 Workspace 文件。")
        }
        return .allow
    }

    private func matches(_ pattern: String, in command: String) -> Bool {
        command.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private var networkPattern: String {
        #"(^|[;&|]\s*)(curl|wget|ssh|scp|sftp|nc|ncat|socat|telnet|ftp)\b|\b(git\s+(clone|fetch|pull|push)|pip3?\s+install|npm\s+(install|ci)|pnpm\s+install|yarn\s+install|apk\s+add|apt(-get)?\s+install)\b"#
    }

    private var hostPathPattern: String {
        #"(^|[\s'\"])(~|/Users/|/private/|/Applications/|/Library/|/System/|/Volumes/)"#
    }

    private var processEscapePattern: String {
        #"\b(nohup|mount|umount|chroot|unshare|nsenter|launchctl|systemctl)\b|:\(\)\s*\{\s*:\|:&\s*;\s*\}|(^|[^&])&\s*$"#
    }

    private var infiniteLoopPattern: String {
        #"\bwhile\s+(true|:)\b|\bfor\s*\(\s*\(\s*;\s*;\s*\)\s*\)"#
    }

    private var policyBypassPattern: String {
        #"\beval\b|\b(base64\s+(-d|--decode)|openssl\s+base64\s+-d|xxd\s+-r\s+-p)\b[^\n|]*\|\s*(sh|bash|zsh|python3?)\b|\$\([^)]*(base64|xxd|printf[^)]*\\x)"#
    }

    private var destructivePattern: String {
        #"(^|[;&|]\s*)(rm\b|truncate\b|shred\b|dd\b)|\bfind\b[^\n]*\s-delete\b|\bgit\s+(clean\b|reset\s+--hard\b)|(^|[^>])>{1,2}\s*[^&]"#
    }
}
