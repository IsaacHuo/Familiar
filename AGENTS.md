## Project Context

Familiar is a native, safe, inspectable personal AI agent for iPhone. Chat / Project / Files are the product objects; Memory is system behavior and Run is execution history. Project is the long-lived work unit, Chat is the interaction entry, and the single-Agent Runtime is the execution kernel.

- Core stack: SwiftUI, SwiftData, URLSession, WebKit, Keychain.
- Minimum deployment target: iOS 26. Do not add fallback branches for older systems; keep only gates for newer versions (e.g. iOS 26.1, iOS 27) and the Reduce Transparency fallback.
- The implemented scope includes one Agent with Lazy Tools, BYOK model access (default DeepSeek), local Chat history, Projects, canonical File/FileVersion, Context Compiler, scoped Skills and Memory, Web search/fetch, native Apple tools, the bundled iSH/Alpine guest for Shell and document generation, local document processing, image input and speech transcription. HTTP MCP discovery and approved calls are connected. No Router, Planner, multi-Agent, background execution or cross-restart continuation.
- The current phase adds no new features; it makes existing features work and look native. See PLAN.md.
- The app has no account system, login, backend database, Supabase dependency, managed quota, subscription, entitlement flow, cloud sync, arbitrary code execution, or multi-Agent orchestration.
- Familiar never reads academic-system or other app data.
- Providers use user-supplied API keys or the connected Kimi Code/Codex/OpenRouter external sign-in flows. Credentials remain in the device Keychain and requests go directly from iOS to the selected Provider. There is no Familiar account system.
- The Agent Runtime only understands typed tool definitions, calls, results, policy decisions, and runtime events. Apple frameworks remain behind native tool adapters.
- Permissions and write authorization are enforced in Swift code. Level-2 local writes (built-in reversible file/workspace writes, memory writes from the approved memory flow, declarative dependency installs from the configured source, preflight-approved offline Shell) execute automatically with real receipts and session Undo; Shell must create a checkpoint before mutation. Level-3 external effects (calendar/reminder create and update, notifications, clipboard write, save to Photos, alarm scheduling, skill install, trusted MCP) ask once and default to "always allow this kind", matched by work scope plus capability version, not by argument hash; deletes, alarm cancel and untrusted MCP ask every time with no reusable grant. A model cannot authorize its own action.
- System entries provide input provenance only and never grant write authorization.
- Ordinary Chat has no Project (`conversation.project == nil`); only explicit creation creates a Project. Ordinary Chat uses global defaults and conversation-owned Files, Workspace, Environment and Memory. `FamiliarWorkScope.project(id)` and `.conversation(id)` isolate ownership and authorization, even for the same UUID. Only explicit global Memory crosses ordinary Chats.
- Storage uses one current schema without a historical migration chain. Business generation `5-work-scopes` performs the user-approved one-time business reset, preserving Keychain, model/search configuration and appearance preferences; subsequent store failures enter recovery without another reset.
- Conversation history is local SwiftData. Keep transient streaming text out of broad persistence invalidation and persist only at explicit checkpoints and terminal states.
- Markdown, code highlighting, Mermaid, and KaTeX are rendered from bundled local resources in a non-persistent WebKit view.
- Use native iOS liquid-glass effects.

## Documentation

Repository knowledge is split by responsibility; read in this order:

```text
1. AGENTS.md (this file)
2. state/CURRENT.md      — current phase, focus, known problems, next
3. state/ARCHITECTURE.md — code-verified module/schema/data-flow
4. docs/                 — design and planning (what we intend to build, and why)
5. logs/                 — reusable debugging/investigation knowledge
6. actual code
```

- `state/` is the **current truth** and must describe reality, not intention. Verify against code before editing; design goals belong in `docs/`, never fake current state to match a design.
- `docs/` is design and planning; it may describe capabilities that do not exist yet. Do not copy `state/` content into `docs/`.
- `logs/` holds only reusable investigation knowledge (symptom → root cause → fix), not activity history.
- After a task that changes architecture, module boundaries, major feature status, or the current development focus, consider updating `state/CURRENT.md` and `state/ARCHITECTURE.md`. Small UI tweaks and bug fixes do not require it.
- Do not duplicate git history in Markdown.
- Read root `PLAN.md` after the current-state documents when continuing the product convergence work. It is the cross-chat task ledger. Update the active slice, completed implementation checkboxes, verification evidence, and next task at each stage; keep real-service/device acceptance separate from compilation.

## Engineering Principles

### Verification

- Verify code changes with an arm64 iOS Simulator build using a concrete arm64 Simulator destination (not `generic/platform=iOS Simulator`, which fails to link iSH).
- Run the narrowest relevant unit tests on one Simulator. UI slices may boot one Simulator to capture production-page screenshots (light/dark, large Dynamic Type). iSH slices may run signed device tests and `log stream` on a connected device; never change signing or erase data.
- A test or Simulator command that shows no progress within 3 minutes is treated as hung: kill it, record the cause, and do not block the slice on retries.
- A slice is complete only after executed tests, screenshots reviewed by the owner and owner sign-off on a physical device. Compilation alone is not completion.

### Git Workflow

- Develop directly on `main` by default. Do not create a new branch unless the user explicitly requests one.

### 1. Prefer Simplicity

Choose the simplest implementation that fully meets the current requirements.

Avoid speculative abstractions, unnecessary configuration, indirection, and infrastructure that is not required by the current product.

Complexity must justify itself.

### 2. Build in Working Layers

Grow the system incrementally.

Start with the smallest version that works end to end, then add each new capability on top of a product that already works.

Never trade a working product for unfinished complexity.

Each development step should leave the system in a usable state.

### 3. Do Not Preserve Obsolete Compatibility

Do not preserve backward compatibility unless explicitly required.

When an old path, API, implementation, or architecture becomes obsolete, remove it instead of adding compatibility layers, fallbacks, adapters, migrations, or duplicated behavior.

Prefer one clear current implementation over multiple historical paths.

### 4. Keep Responsibilities Separated

Keep components modular and concerns clearly separated.

Each module, type, service, or component should have a clear responsibility and a minimal interface.

Avoid tightly coupling unrelated behavior.

Do not introduce abstraction solely for the sake of abstraction; modularity should make the system easier to understand, modify, and verify.

### 5. Reuse Existing Dependencies First

Lean on the dependencies already present in the project before writing custom implementations or adding new packages.

Do not assume an existing library lacks a required capability without checking its documentation, APIs, and types first.

Avoid duplicating functionality that the project already has.

### 6. Prefer Established Libraries

Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability.

Do not reimplement common functionality without a clear technical or product reason.

Before adding a dependency, verify that it meaningfully simplifies the implementation and does not introduce disproportionate maintenance cost.

### 7. Design for the Long Term

Make architectural decisions that remain sound as the product grows.

Do not accept temporary stopgaps that are intentionally meant to be replaced later.

A simple implementation is preferred, but it should still have a clean path for extension.

Avoid accumulating known structural debt for short-term convenience.

### 8. Study Proven Products First

Before designing a solution, study how established products solve the same or similar problem.

Prefer proven interaction patterns, architectural conventions, terminology, and workflows over inventing a new approach from scratch.

Understand why existing patterns work before deviating from them.

Introduce a novel approach only when the product has a concrete requirement that established patterns do not adequately address.
