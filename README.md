<p align="center">
  <img src="website/public/assets/app-icon.png" width="112" alt="Familiar app icon">
</p>

<h1 align="center">Familiar</h1>

<p align="center">
  A native, safe and inspectable personal AI workspace for iPhone.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/IsaacHuo/familiar/actions/workflows/pages.yml"><img src="https://github.com/IsaacHuo/familiar/actions/workflows/pages.yml/badge.svg" alt="Website deployment"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-0A84FF?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <img src="https://img.shields.io/badge/Platform-iPhone-111111" alt="iPhone only">
  <img src="https://img.shields.io/badge/Architecture-BYOK-6D5DFB" alt="Bring your own key">
</p>

<p align="center">
  <a href="https://isaachuo.github.io/familiar/">Website</a> ·
  <a href="https://isaachuo.github.io/familiar/privacy/">Privacy</a> ·
  <a href="https://isaachuo.github.io/familiar/support/">Support</a>
</p>

---

## Screenshots

<table>
  <tr>
    <td align="center"><img src="screenshots/chat.png" width="210" alt="Chat"></td>
    <td align="center"><img src="screenshots/drawer.png" width="210" alt="Drawer"></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/settings.png" width="210" alt="Settings"></td>
    <td align="center"><img src="screenshots/permissions.png" width="210" alt="Permissions"></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/storage.png" width="210" alt="Storage"></td>
    <td></td>
  </tr>
</table>

*Chat · Drawer · Settings · Permissions · Storage*

## Overview

> **Familiar is a native, safe and inspectable personal AI workspace.** Projects are the long-lived work unit, chat is the primary entry, and native tools plus read-only Web form the current execution surface. The single-Agent Runtime is the execution kernel.

Familiar turns the iPhone's native capabilities into a composable runtime without adopting a Linux execution environment, Apple Intelligence dependency or multi-agent orchestration. Project, versioned document resources, and Markdown/text artifacts are implemented; writable workspace capabilities beyond artifacts and runtime resumable execution remain the next product layer.

The app is BYOK-only: users bring their own model API Key, model requests go directly from the device to the selected Provider, and conversations, attachments and tool records stay on the device. When web tools are used, search queries go directly to DuckDuckGo and page requests go directly to the selected public HTTPS site.

> Familiar is under active development. AI output may be inaccurate and should not be the sole basis for medical, legal, financial or other high-risk decisions.

## Highlights

- **iPhone-native Agent Runtime** — a single primary Agent that plans with tools and executes through native iOS frameworks; no Linux environment, no Apple Intelligence dependency.
- **Tools as the core abstraction** — Calendar, Vision, PDF, Maps and more are just Tools registered in a Capability Registry; each tool is small, orthogonal and composable.
- **Native First** — reuse EventKit, Vision, MapKit, PDFKit, Photos and Foundation instead of reimplementing calendar, OCR, maps or document rendering.
- **Project workspace v1** — projects share an instruction and versioned local document resources across chats; resources use independent protected storage and immutable Run context references. Markdown/text artifacts are stored per project under structured confirmation. Writable workspace capabilities beyond artifacts remain planned.
- **Code-enforced authorization** — low-risk reads run automatically; current EventKit writes require structured per-action confirmation and provide an in-process, one-shot Undo after success.
- **Runtime-event-driven UI** — the timeline renders Agent events (model thinking, tool progress, approval, success and failure) instead of each tool owning its own UI.
- **Local-first and BYOK** — API Keys are stored per Provider in the iOS Keychain; requests never pass through Familiar servers.
- **Multi-provider catalog** — OpenAI, Anthropic, Gemini, DeepSeek, Groq, xAI, OpenRouter, Qwen, Kimi, GLM, MiniMax, SiliconFlow, and custom OpenAI-compatible endpoints.
- **Local document conversion** — AnyDoc converts Office, OpenDocument, RTF, EPUB, CSV and PDF files to Markdown on the device; scanned PDFs use Vision OCR.
- **System entry** — Share selected text, web links or documents into an App Group inbox; typed Deep Links restore local context; optional local notifications return to completed or failed Runs; protected on-device Spotlight results reopen local conversations; Siri and Shortcuts expose `Ask Familiar`, `Process with Familiar` and `Open Familiar`.
- **Rich answer rendering** — local Markdown, syntax highlighting, tables, block quotes, Mermaid, KaTeX, code copying and safe external links.
- **Voice transcription** — Apple Speech and `AVAudioEngine` generate editable text drafts; original recordings are not stored.
- **Bilingual UI** — complete Simplified Chinese and English resources, Light and Dark Mode, Dynamic Type, VoiceOver, Reduce Motion and Reduce Transparency.

## Target architecture

Familiar is evolving toward six layers. The diagram includes planned capabilities and is not a current implementation inventory:

```text
┌─────────────────────────────────────────┐
│             System Entry Layer          │
│ Chat / Share / Notifications / Widgets  │
│ Spotlight / App Intents / Shortcuts     │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│               Agent Runtime             │
│                                         │
│ Agent Loop / Context Assembly           │
│ Model Router / Tool Router              │
│ Run / Step State                        │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│            Capability Registry          │
│                                         │
│ System Tools          Workspace Tools   │
│ Calendar              File              │
│ Reminder              PDF               │
│ Contacts              Text              │
│ Photos                Image             │
│ Maps                  Audio             │
│ Weather               Web               │
│ Location              Structured Data   │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│           Execution Policy Layer        │
│ Availability / Permission / Approval    │
│ Validation / Timeout / Cancellation     │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│              Native Layer               │
│ EventKit / Vision / MapKit / WebKit     │
│ Photos / PDFKit / Core ML / Foundation  │
└─────────────────────────────────────────┘
            + State Layer
  Session / Workspace / Memory
  Artifacts / Trace / History
```

Current implementation: ordinary conversations remain available alongside Project-owned chats. The runtime has a bounded sequential tool loop, nine statically registered tools (including project artifact writes), structured EventKit approval, read-only Web search/fetch, Project instructions/resources, immutable input context records, artifact storage, and summary Run/Step persistence. Durable Memory, Skills, MCP, and runtime resumable runs are not yet implemented.

```mermaid
flowchart TD
    Entry[System Entry Layer] --> Runtime[Agent Runtime]
    Runtime --> Registry[Capability Registry]
    Registry --> Policy[Execution Policy Layer]
    Policy --> Native[Native Layer: EventKit Vision MapKit PDFKit ...]
    Runtime --> State[State Layer: Session Memory Trace]
```

The Agent Runtime is the key layer: it knows only `ToolDefinition`, `ToolCall` and `ToolResult`. It never touches EventKit, Vision, HealthKit or MapKit directly; those live behind the Capability Registry and Execution Policy.

### System entry

System entry points are prioritized:

| Priority | Entry |
| --- | --- |
| **First** | ① Familiar App · ② Share Extension · ③ System notifications / Deep Links |
| **Second** | ④ Widgets / Controls · ⑤ Spotlight and other lightweight system entries |
| **Compatibility** | ⑥ App Intents · ⑦ Shortcuts |

The current System Entry layer includes the Familiar App, a Share Extension, typed Deep Links, opt-in local Run notifications, a protected on-device Spotlight conversation index, a launcher Widget and Control, three App Intents and bilingual App Shortcuts. The Widget opens a new editable draft and the Control opens Familiar without replacing the current context. Shared content is staged locally and Deep Links only restore or prefill context. Run notifications use generic text and carry only a local Run or conversation identifier; they do not use remote push or provide background execution. Spotlight indexes only bounded conversation titles, modification dates and local identifiers, never transcripts or attachment metadata. `Ask Familiar` and `Process with Familiar` explicitly start the existing in-app send path; `Open Familiar` changes no draft or conversation. None of these entries can authorize a tool action.

App Intents stay outside the Agent core. Their text input is bounded, they never read Keychain or call a Provider directly, and they refuse to overwrite an unsent draft. The full Capability Registry is not duplicated into App Intents.

## Agent runtime

Familiar uses a single-Agent-first design with a composable tool loop:

```text
User
  → AgentRun
  → Conversation context assembly (current) / ProjectContextAssembler (target)
  → Model
  → Tool Call?
       ├── No ──→ Final Answer
       └── Yes
           → Tool Registry
           → Policy Engine
           → Execute Tool
           → ToolResult
           → Context
           → Model
           → continue
until: final answer / cancelled / failed / max steps
```

The agent loop is bounded: a maximum number of iterations, tool-result length limits and context limits enforced by model capability. Duplicate tool calls within a run are rejected; a write can be submitted successfully only once per run.

## Tools

Tools are strongly typed in Swift; the Registry stores `AnyFamiliarTool` values. The current protocol uses a typed `Input` and returns a `FamiliarToolOutcome`:

```swift
protocol FamiliarTool {
    associatedtype Input: Decodable & Sendable

    var manifest: FamiliarToolManifest { get }
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome
}
```

The current `FamiliarToolManifest` carries:

```text
FamiliarToolManifest
  name
  title
  description
  parameters
  effect        read / write / destructiveWrite
  risk          low / high
  requirements  EventKit, Calendar permission, ...
```

Internally Familiar separates, following the spirit of MCP but in native Swift:

- **Current resources** — conversation history and extracted message attachments (application-controlled)
- **Current tools** — two device-information, two read-only Web, one project-artifact and four EventKit tools (model-controlled)
- **Target resources** — Project files, URLs, Artifacts and scoped Memory
- **Target instructions** — base policy, Project instructions and Skills (user-controlled)

MCP is an adapter, not the kernel. A future remote HTTPS client will convert MCP Tools into Familiar manifests and continue to apply Familiar policy; MCP is not currently implemented.

## Capability Registry

The target Registry is a core asset organized into two capability families:

| Native System | Native Workspace |
| --- | --- |
| Calendar | File |
| Reminders | PDF |
| Contacts | Text |
| Photos | Image |
| Maps | Audio |
| Location | Video |
| Weather | CSV / JSON |
| Health | Archive |
| Notifications | Document |
| Clipboard | Web |

The current Registry is a startup-supplied dictionary of nine tools with EventKit availability filtering. Native Workspace in the table is a target built from Project + Resource + Artifact; runtime discovery, installation, versioning and project binding are not implemented.

## Permission model

Current production authorization behavior:

| Operation | Default behavior |
| --- | --- |
| Read + low risk | Automatic |
| Reversible write | Structured confirmation, then in-process one-shot Undo |
| Inferred write | Structured confirmation |
| Sensitive read | Permission / policy |
| Destructive | Confirm |
| Financial / external consequential | Strong confirmation |

Permissions are controlled by code, not by prompt: the model cannot bypass HealthKit permissions, delete confirmations or sensitive-data policy with a sentence.

The target authorization model may avoid repeated confirmation only when a user action creates an auditable, single-use grant that matches the capability, normalized arguments, scope and expiry. Share Extension, App Intent and Deep Link provenance never grants write authority.

## Provider support

| Protocol | Providers |
| --- | --- |
| OpenAI Chat | OpenAI, DeepSeek, Groq, xAI, OpenRouter, Qwen, Kimi, GLM, MiniMax, SiliconFlow, custom OpenAI-compatible |
| Anthropic Messages | Anthropic |
| Gemini generateContent | Gemini |

Each Provider has its own Keychain item, endpoint configuration, headers and model-catalog policy. Model capabilities are marked by `providerID + modelID`; unknown custom models are text-only by default.

The model layer uses a simple `FamiliarModelProvider` abstraction with OpenAI Chat, Anthropic Messages and Gemini adapters. The next phase establishes deterministic Agent benchmarks before any model splitting or local-model work.

## Document pipeline

All documents are first copied to the App's private directory and then converted locally.

| Input | Local processing |
| --- | --- |
| DOC, DOCX, DOCM | AnyDoc → GitHub-Flavored Markdown |
| PPT, PPS, POT, PPTX, PPTM, PPSX, PPSM | AnyDoc → GitHub-Flavored Markdown |
| XLS, XLSX, XLSM, XLSB | AnyDoc → GitHub-Flavored Markdown |
| ODT, ODS, ODP | AnyDoc → GitHub-Flavored Markdown |
| RTF, EPUB, CSV | AnyDoc → GitHub-Flavored Markdown |
| Text PDF | AnyDoc / pdf-inspector → Markdown |
| Scanned or mixed PDF | AnyDoc first; PDFKit + Vision OCR for pages without a text layer |
| TXT, MD, Markdown | Encoding validation and lossless text pass-through |

Only the converted Markdown and filename enter the model request. Original document bytes, local paths and security-scoped URLs are never sent to Firecrawl or the selected model Provider.

Image preprocessing is a Tool, not a forced pipeline: an image goes to Vision OCR, barcode detection or the multimodal model based on what the Agent decides the task needs, not by default OCR.

## Rendering

Assistant output is rendered by a bundled, non-persistent `WKWebView` using local resources only.

Supported output includes CommonMark-style Markdown, syntax-highlighted code blocks with copy, tables, block quotes, lists, Mermaid diagrams, KaTeX expressions and safe external links.

## Privacy and security model

- No Familiar account or login.
- No Familiar-owned chat backend or cloud database.
- No subscription, entitlement or managed quota system.
- API Keys are stored per Provider in iOS Keychain.
- Conversation history, attachments and tool records are stored locally.
- Streaming tokens and pending confirmations are not broadly persisted.
- Documents are converted locally; only converted text is sent with a user-initiated request.
- Calendar and reminder access is requested only when the corresponding tool is invoked.
- Writes require per-action confirmation or an explicit reversible Undo path.
- Website code contains no advertising, analytics or tracking scripts.

## Technology stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI |
| Local persistence | SwiftData |
| Networking | URLSession, SSE streaming |
| Secrets | iOS Keychain |
| Rich content | WebKit with bundled Markdown, Mermaid and KaTeX resources |
| Native tools | EventKit |
| Documents | AnyDoc Rust core, PDFKit, Vision |
| Voice input | Speech, AVFoundation |
| Photos | PhotosPicker |
| Website | Vue 3, Vite, GitHub Pages |

## Repository structure

```text
Familiar/
├── Agent/          Agent runtime, tool loop and confirmation events
├── AnyDoc/         Swift interface to the embedded AnyDoc engine
├── App/            App entry point and model container
├── Artifacts/      Project artifact store and artifact tool
├── Attachments/    Private storage, conversion and OCR pipeline
├── Data/           Provider adapters, Keychain and model catalog services
├── Domain/         Provider, message and capability models
├── EventKit/       Calendar and reminder services/tools
├── Persistence/    SwiftData schema and migration chain
├── Presentation/   SwiftUI screens, composer and message rendering
├── Resources/      Localizations, assets and bundled renderer resources
├── Speech/         Native voice transcription
├── Support/        Theme and platform compatibility helpers
├── SystemEntry/    Deep links, intents, notifications and Spotlight
└── Web/            Read-only web search/fetch with restricted HTTP client

FamiliarWidgets/    Home/Lock Screen launcher Widget and Control Center control

Shared/             App-group inbox and control intent (app + extensions)
Vendor/
├── AnyDocBridge.xcframework/
└── AnyDocBridgeRust/

docs/               Design and planning (what we intend to build)
state/              Current implementation truth (code-verified)
logs/               Reusable debugging and investigation knowledge
website/            Vue/Vite website, privacy policy and support pages
Scripts/            Reproducible AnyDoc XCFramework build script
```

Documentation is organized by intent and split across three directories (see [`docs/README.md`](docs/README.md) for the model): `docs/` holds design and planning, `state/` holds the code-verified current implementation (`state/CURRENT.md` first, then `state/ARCHITECTURE.md`), and `logs/` holds reusable investigation knowledge.

## Requirements

- Apple Silicon Mac
- Xcode 26 or later
- iOS 18 or later
- iPhone target
- A valid API Key for at least one supported model Provider

Rust is not required for normal App builds because the arm64 AnyDoc XCFramework is committed to the repository.

## Build the iOS app

```bash
git clone https://github.com/IsaacHuo/familiar.git
cd familiar
open familiar.xcodeproj
```

Select the `Familiar` scheme and an iPhone destination. API Keys are configured at runtime in the App and must never be committed to the repository.

Command-line build example:

```bash
xcodebuild \
  -project familiar.xcodeproj \
  -scheme Familiar \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Rebuild AnyDoc

```bash
./Scripts/build-anydoc-xcframework.sh
```

The script builds only `aarch64-apple-ios` and `aarch64-apple-ios-sim`.

## Build the website

```bash
npm --prefix website ci
npm --prefix website run build
```

## Intentional scope boundaries

Familiar does not currently include:

- iPad support
- Account systems
- Writable workspace beyond project artifacts, and runtime resumable Run execution (data contracts exist; not wired into execution yet)
- Familiar-hosted model proxying
- Subscription or entitlement flows
- Linux / iSH execution environment
- Shell or arbitrary code execution
- Multi-agent, subagents or agent graphs
- Complex RAG or vector databases
- MCP Server on iPhone (a client may arrive later)
- Core ML LLM or Apple Intelligence dependency
- Real-time voice conversation
- Calendar/reminder modification or deletion
- Autonomous browser actions, JavaScript execution or recursive crawling

## Third-party software

Familiar embeds AnyDoc and SwiftSoup under the MIT License. The required notices are included in:

- `Vendor/AnyDocBridgeRust/LICENSE.anydoc`
- `Familiar/Resources/ThirdPartyNotices.txt`

Other bundled renderer resources retain their respective upstream notices and licenses.

## Support

- Product support: <https://isaachuo.github.io/familiar/support/>
- Privacy questions: <https://isaachuo.github.io/familiar/privacy/>
- Bug reports: <https://github.com/IsaacHuo/familiar/issues>

When reporting a problem, do not include API Keys, private conversations, calendar data, reminders, documents or other sensitive information.
