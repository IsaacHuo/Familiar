# Familiar

A native AI Q&A app for iPhone. The current focus is a source-backed Telegram iOS UI alignment, starting with chat. The owner performs final visual acceptance on a physical device.

[简体中文](README.zh-CN.md) · [Website](https://isaachuo.github.io/Familiar/) · [Privacy](https://isaachuo.github.io/Familiar/privacy/) · [Support](https://isaachuo.github.io/Familiar/support/)

## Capabilities and boundaries

- BYOK and connected external provider sign-in; credentials stay in device Keychain and requests go directly to the selected service.
- Local chat history, streaming, Markdown, code, tables, math, Mermaid, images and speech transcription.
- Optional Projects, canonical File/FileVersion, scoped Memory and Skills.
- One Agent with Lazy Tools for Web, native Apple capabilities, MCP and the bundled iSH/Alpine document environment.
- Swift-enforced authorization, real receipts and Undo for supported local writes, valid grants for external effects, and confirmation for every delete.

Requires iOS 26, Swift 6 and a compatible Xcode SDK. SwiftUI/UIKit, SwiftData, URLSession and WebKit form the core stack. Files, Chat and Settings remain the three tabs. There is no Familiar account, backend, cloud sync, subscription, multi-agent system, background execution or cross-restart continuation. Compilation and source inspection are distinct from executed tests, live services and device acceptance.

## Development

Open familiar.xcodeproj and select scheme Familiar. AnyDoc/iSH binaries and local Skill dependencies are under Vendor; maintain them through the existing Scripts. Do not alter signing or erase data.

Work on main by default. Use build-for-testing with a concrete arm64 Simulator destination; generic Simulator may select x86_64, unsupported by iSH. The current agent workflow compiles the App and test targets only, without booting Simulator or executing tests. See [AGENTS](AGENTS.md) and the [verification checklist](docs/11-verification-and-release-checklist.md).

## Documentation

Start with [current state](state/CURRENT.md), [architecture](state/ARCHITECTURE.md) and [active work](PLAN.md). The [documentation index](docs/README.md) separates design, implementation facts and historical evidence.

Telegram reference commit: f1dd7a2. The [320-item alignment ledger](docs/telegram-ios-ui-checklist.md) tracks source, implementation, compilation and owner acceptance independently. The [UI specification](docs/03-ui-ux-design.md) is the current design authority.

## License and data

[GPL-3.0](LICENSE). Third-party attribution is in Familiar/Resources/ThirdPartyNotices.txt and the iSH notices. Chat wallpaper is bundled and Markdown never automatically fetches remote images. Third-party model service charges and policies apply; see [data and privacy boundaries](docs/05-local-data-and-privacy.md).
