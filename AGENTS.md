## Project Context

Familiar is a standalone iOS chat app.

- Core stack: SwiftUI, SwiftData, URLSession, WebKit, Keychain.
- Minimum deployment target: iOS 17.
- The current product scope is direct chat Q&A only.
- The app has no account system, login, backend database, Supabase dependency, managed quota, subscription, entitlement flow, web research, personal-data context, external actions, or Artifact flow.
- Familiar never reads academic-system or other app data.
- DeepSeek is BYOK-only. Keys remain in the device Keychain and requests go directly from iOS to DeepSeek.
- Conversation history is local SwiftData. Keep transient streaming text out of broad persistence invalidation and persist only at explicit checkpoints and terminal states.
- Markdown, code highlighting, Mermaid, and KaTeX are rendered from bundled local resources in a non-persistent WebKit view.
- Use native iOS 26 liquid-glass effects with iOS 17 fallbacks.
