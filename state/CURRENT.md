# Current State

Last reviewed: 2026-10-01. B1/B2/C1/C2/C3/C6/C7 implementation, static checks and arm64 test-target compilation are verified. No new runtime or device acceptance is claimed.

## Current Focus

Familiar is converging around native iPhone Chat, long-lived Project context and one Agent Runtime. The cross-chat implementation and acceptance ledger is [PLAN.md](../PLAN.md).

The target Harness is **One Agent + One Loop + Lazy Tools + Progressive Escalation**. Stability and product logic precede the full-app visual pass. OpenMinis is a reference, not a parity target. No task-complexity Router, fixed planning pipeline, new orchestration kernel, background execution or cross-restart continuation is being added.

Current slice B1 removes mandatory planning. Project and Daily Chat can now return an answer on their first model request without task_plan or unrelated tool evidence. task_plan is an optional display checklist. The loop no longer withholds answer text to force a plan, enforces ordered step completion, binds publication to a promised deliverable ID, runs automatic delivery repair, or persists duplicate execution-state snapshots. Actual tool/approval/result boundaries and the single runFinished outcome remain.

B2 now separates the frozen permitted catalog from the current model request. The initial request exposes only current_date_time, ask_user and tools_load. The model selects at most two extension groups; each successful load replaces the active extension schemas. Guessed/unexposed names fail without execution, including when batched with a loader. Project and Skill scopes share one base-tool rule, permissions remain checked at execution, and attempted calls consume the Run budget.

Native group metadata carries no full schemas. HTTP MCP discovery runs only when an enabled server group is requested, caches that Run's definitions, pages descriptions and requires exact tool selection before exposing remote schemas. Selected manifests are persisted at the success boundary. iSH is not prepared at App startup: actual Shell/Environment operations prepare it on demand. Shared preparation has cancellable waiters; cancelling a Run does not stop private shared setup, but prevents that Run from starting its command. Real guest behavior is still unaccepted.

C2 now journals committing invocations before action calls and reserves exact write fingerprints at that point. Failed or uncertain writes cannot be blindly replayed in the same Run; interrupted journals stay uncertain. Necessary outputs and durable Undo are saved before success events. Local rollback/finalize hooks compensate new Artifact bytes and Environment swaps; external writes are never silently undone.

Artifact edit now creates an independent successor version instead of replacing old bytes. Artifact deletion/Undo stages the directory until the metadata save succeeds. Undo results are cached through save retries, and native durable Undo is marked unavailable before action so a crash does not cause automatic replay. Editing/regenerating a history segment with committed/uncertain actions is blocked, preserving receipts; pure read history remains regenerable.

C3 now prepares and validates the frozen input before inserting the conversation, user message or committed attachment files. Protected Project input, the pending turn and base schemas must fit together; old history remains eligible for automatic compaction. Vision evidence is checked again before submission, and supported image input fails explicitly when bytes cannot be read. Only a successful submission save consumes the draft; the same validated snapshot enters the Run. C7 uses read-only keyword candidates and stages lastUsedAt only for memories admitted by the compiler, in the accepted message save.

## Implemented Paths

- Chat: direct launch, protected Daily Chat Project, drafts and attachments, editable speech transcription, streaming text/reasoning, ordered Markdown/tool blocks, approval/clarification, cancellation, local history, retry, manual compaction, branching, project move and text export.
- Models: local Provider instances and independent Keychain identities, four text wire protocols, Kimi Code/Codex/OpenRouter sign-in implementations, model groups and reported usage. The catalog is no longer DeepSeek-only. No Familiar account or hosted backend exists.
- Project: instructions, optional model override, versioned files/web/text Resources, frozen ContextSnapshot, conversations and Artifact history. Chat remains the execution entry.
- Tools: typed manifests, capability availability, scoped authorization, structured proposals/results, read-only Web, EventKit, native adapters, controlled Workspace/Shell and Artifact output. A model cannot authorize its own actions.
- Memory: global/project/conversation records, user-confirmed remember proposals, frozen-search selection, budgeted Context Compiler injection and Settings management. Approved memory is persisted through the Run commit callback before success events; save failure becomes a tool failure.
- Skills: instruction selection and scope narrowing, Project binding, checked immutable package preparation/import with SKILL.md and hashed resources. Resource packages do not grant native permissions or automatically run installation scripts. Real package/guest tasks are unverified.
- MCP: Lazy HTTP discovery and approved calls, per-run registry snapshot, conversation/project/global bindings. STDIO, OAuth and full Schema coverage are unfinished.
- Artifact: text writes, readback, real-file signature/content/hash validation and publication, lineage/version lists, Quick Look and sharing. Publication no longer requires a task_plan; optional requiredText/minimumSources checks are supplied on the publish call itself.
- Environment: bundled iSH/Alpine, preparation lifecycle, Project Workspace mounts, dependency preparation, bounded output/network/resource policy, checkpoints and on-demand shared preparation. Guest operation is not accepted on a physical device.
- UI: existing semantic Theme/Typography/Spacing/Radius/Motion and availability-gated native glass. Full component/page consistency remains unfinished.

## Known Problems

1. **B3 cleanup remains**: unused Capability/Grant paths and the cloud-only production wrapper around unfinished local-model routing still need a reference audit. Lazy tool exposure is implemented; real-model group selection and cancellation still need acceptance. Character budgeting now includes parameter schemas and load reports, but remains a character estimate, not tokenizer accounting.
2. **Crash windows remain unaccepted**: pre-action journals, persistence gating, local compensation and Undo caching are implemented. A process exit immediately after an external effect can still leave an uncertain journal without a full receipt; it blocks blind regeneration, not the original effect. Native permissions, disk-full and process-kill boundaries remain device-unverified.
3. **Web capture grows long-term context automatically**: every fetched page is imported into the conversation's Project, including Daily Chat. All Project resources are injected as protected input; unrelated searches can increase later context cost. C4 will make retention explicit.
4. **Submission acceptance is not Provider acceptance**: local preflight and save failures now retain the draft, but later network/Provider/compaction failures can still occur after an accepted message. Budgeting is a local character estimate; signed-device draft cancellation, Vision and storage-failure behavior remain unverified.
5. **Artifact acceptance**: edit and publish now use independent versions and local deletion compensation. Version browsing, sharing, Undo and filesystem/database recovery still lack device/visual acceptance.
6. **Execution-layer concepts dominate navigation**: Project and Settings expose Environment, Skills, MCP, Capability, Shell, budgets and diagnostics at the main level. Voice-provider management has duplicate entries. Markdown CSS uses independent colors; the visual fixture still contains a ToolChips tree unused by the production timeline.
7. **No cross-restart execution**: cursor/invocation records are audit data; startup ends interrupted runs and pending interactions. Do not advertise paused/resumable execution. Reliable background execution is absent.
8. **Acceptance gaps**: real Provider authentication/stream/tools/cancellation, DuckDuckGo/network behavior, MCP servers, system permissions, iSH, complex documents, speech, Face ID and device visual/accessibility behavior remain unaccepted in this review.
9. **Test-list gaps**: the release-suite script historically omitted imported contracts/group boundaries/execution contracts. The Harness and LazyTool suites are now listed, but the complete list still needs F1 reconciliation; device guest tests skip on Simulator.
10. Keychain coverage is unavailable in unsigned hosts when SecItem returns errSecMissingEntitlement. Skips/unverified scenarios are not successful credential tests. Store damage, disk-full and signed upgrade behavior still require device checks.
11. Core AI is an unavailable adapter contract; FamiliarMac is a separate shell without the shared iOS execution/data path. Neither is part of this convergence acceptance.
12. Existing voice/OAuth compiler warnings need E5 review. Runtime/performance defects are not inferred solely from those warnings.

## Verification Evidence

- Original-project audit baseline: Xcode 27.0, Debug arm64 generic iOS Simulator build-for-testing, TEST BUILD SUCCEEDED. App, extensions and test targets compiled. Simulator was not started; tests were not executed; no real credentials or device actions were used.
- B1: regression cases added for a direct response with nil/Daily/custom Project scopes, optional pending checklists, and an approved text Artifact without a prior plan. App, extensions and regression/test targets compiled successfully in an independent DerivedData (TEST BUILD SUCCEEDED). They have not been executed.
- C1: Memory commit-success ordering and save-failure regression targets compiled; final incremental build-for-testing returned TEST BUILD SUCCEEDED. git diff --check and both strings plist checks passed. Tests were not executed and no Simulator was started.
- B2: final original-project arm64 build-for-testing returned TEST BUILD SUCCEEDED. App, extensions and all test targets compiled; git diff --check, script syntax and strings parity (973/973) passed. The 14 new LazyTool regression cases cover initial exposure, group replacement, unexposed calls, Skill scope, MCP selection/paging/failure/deadline/approval, same-batch duplicate writes, loader budget, parameter-schema budget, Project defaults and shared/cancelled preparation. These are compilation checks only; tests and real servers/guest were not run.
- C2/C6: final arm64 build-for-testing returned TEST BUILD SUCCEEDED; 12 new CommitBoundary cases and related existing fixtures compiled. Tests were not executed; no Simulator, real Provider, EventKit/AlarmKit or guest operation was started.
- C3/C7: `/tmp/familiar-send-c3-verified-20261001-build.log` returned TEST BUILD SUCCEEDED for the original Debug arm64 generic iOS Simulator build-for-testing. Nine new SendPreflight cases and the revised Memory scope/usage case compiled. They cover combined protected/pending/schema budgets, retained compaction, Vision evidence, staged versus frozen paths, missing image bytes and budgeted memory usage/rollback. They were not executed; Controller draft/Keychain/real-provider behavior is not a runtime pass. Static diff, shell syntax, strings plist and 980/980 key parity checks passed.
- Earlier CURRENT revisions recorded executed deterministic suites in August/September. Those records are historical evidence, not proof of the current imported Provider/Harness behavior. New real-service/device acceptance remains blank in PLAN.md.

## Next

1. B2 implementation and compilation are complete; all behavioral/device acceptance remains separate.
2. Next prioritize C4: explicit Web-to-Project retention. C2/C3/C6/C7 implementation and compilation are complete; real-system acceptance remains pending. B3 removes only confirmed unused orchestration paths; it does not add a scheduler or task Router.
3. After C4, continue advanced navigation and UI convergence. Artifact revisions are already immutable; do not add tool breadth before the existing paths are accepted.
4. Converge advanced navigation and the complete SwiftUI/Markdown design system, reusing production components.
5. Verify core real tasks with the owner, then investigate measured performance. Do not resume mechanical feature parity, a plan scheduler, Core AI, background execution or a second Agent.
