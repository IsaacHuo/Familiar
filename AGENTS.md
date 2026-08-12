## Project Context

Familiar is a standalone iOS chat app.

- Core stack: SwiftUI, SwiftData, URLSession, WebKit, Keychain.
- Minimum deployment target: iOS 18.
- The current product scope is direct chat Q&A only.
- The app has no account system, login, backend database, Supabase dependency, managed quota, subscription, entitlement flow, web research, personal-data context, external actions, or Artifact flow.
- Familiar never reads academic-system or other app data.
- DeepSeek is BYOK-only. Keys remain in the device Keychain and requests go directly from iOS to DeepSeek.
- Conversation history is local SwiftData. Keep transient streaming text out of broad persistence invalidation and persist only at explicit checkpoints and terminal states.
- Markdown, code highlighting, Mermaid, and KaTeX are rendered from bundled local resources in a non-persistent WebKit view.
- Use native iOS liquid-glass effects.

## Engineering Principles

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
