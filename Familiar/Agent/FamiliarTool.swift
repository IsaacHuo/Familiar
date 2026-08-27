import Foundation

nonisolated public enum FamiliarToolEffect: String, Codable, Sendable {
    case read
    case reversibleWrite
    case destructiveWrite
}

nonisolated public enum FamiliarToolRisk: String, Codable, Sendable {
    case low
    case sensitive
    case high
}

nonisolated public struct FamiliarToolPresentationPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public enum Name: String, Codable, Sendable {
        case scalar
        case searchResults
        case document
        case contextMatches
        case recordCollection
        case mutationReceipt
        case artifactMutation
        case diff
        case taskList
        case recommendation
        case insight
        case code
        case shareDraft
    }

    public struct Scalar: Codable, Equatable, Sendable {
        public let summary: String
        public let label: String?
        public let value: String

        public init(summary: String, label: String? = nil, value: String) {
            self.summary = summary
            self.label = label
            self.value = value
        }
    }

    public struct SearchResult: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let url: String
        public let snippet: String?

        public init(id: String, title: String, url: String, snippet: String?) {
            self.id = id
            self.title = title
            self.url = url
            self.snippet = snippet
        }
    }

    public struct SearchResults: Codable, Equatable, Sendable {
        public let summary: String
        public let query: String
        public let results: [SearchResult]

        public init(summary: String, query: String, results: [SearchResult]) {
            self.summary = summary
            self.query = query
            self.results = results
        }
    }

    public struct Document: Codable, Equatable, Sendable {
        public let summary: String
        public let title: String?
        public let text: String
        public let mimeType: String?
        public let url: String?
        public let truncated: Bool

        public init(summary: String, title: String?, text: String, mimeType: String? = nil, url: String? = nil, truncated: Bool = false) {
            self.summary = summary
            self.title = title
            self.text = text
            self.mimeType = mimeType
            self.url = url
            self.truncated = truncated
        }
    }

    public struct ContextMatch: Codable, Equatable, Sendable {
        public let resourceID: UUID
        public let versionID: UUID
        public let version: Int
        public let title: String
        public let excerpt: String

        public init(resourceID: UUID, versionID: UUID, version: Int, title: String, excerpt: String) {
            self.resourceID = resourceID
            self.versionID = versionID
            self.version = version
            self.title = title
            self.excerpt = excerpt
        }
    }

    public struct ContextMatches: Codable, Equatable, Sendable {
        public let summary: String
        public let query: String
        public let matches: [ContextMatch]

        public init(summary: String, query: String, matches: [ContextMatch]) {
            self.summary = summary
            self.query = query
            self.matches = matches
        }
    }

    public struct RecordField: Codable, Equatable, Sendable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public let id: String
        public let fields: [RecordField]

        public init(id: String, fields: [RecordField]) {
            self.id = id
            self.fields = fields
        }
    }

    public struct RecordCollection: Codable, Equatable, Sendable {
        public let summary: String
        public let recordType: String
        public let records: [Record]

        public init(summary: String, recordType: String, records: [Record]) {
            self.summary = summary
            self.recordType = recordType
            self.records = records
        }
    }

    public struct MutationReceipt: Codable, Equatable, Sendable {
        public let summary: String
        public let operation: String
        public let targetIdentifier: String?
        public let succeeded: Bool
        public let undoAvailable: Bool

        public init(summary: String, operation: String, targetIdentifier: String?, succeeded: Bool, undoAvailable: Bool) {
            self.summary = summary
            self.operation = operation
            self.targetIdentifier = targetIdentifier
            self.succeeded = succeeded
            self.undoAvailable = undoAvailable
        }
    }

    public struct ArtifactMutation: Codable, Equatable, Sendable {
        public let summary: String
        public let operation: String
        public let identifier: String
        public let title: String
        public let byteSize: Int64
        public let contentHash: String

        public init(summary: String, operation: String, identifier: String, title: String, byteSize: Int64, contentHash: String) {
            self.summary = summary
            self.operation = operation
            self.identifier = identifier
            self.title = title
            self.byteSize = byteSize
            self.contentHash = contentHash
        }
    }

    public struct Diff: Codable, Equatable, Sendable {
        public let summary: String
        public let before: String
        public let after: String

        public init(summary: String, before: String, after: String) {
            self.summary = summary
            self.before = before
            self.after = after
        }
    }

    public enum TaskStatus: String, Codable, Equatable, Sendable {
        case pending
        case running
        case completed
        case failed
    }

    public struct TaskItem: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let status: TaskStatus
        public let detail: String?
        public let progress: Double?

        public init(id: String, title: String, status: TaskStatus, detail: String? = nil, progress: Double? = nil) {
            self.id = id
            self.title = title
            self.status = status
            self.detail = detail
            self.progress = progress
        }
    }

    public struct TaskList: Codable, Equatable, Sendable {
        public let planID: String
        public let title: String
        public let tasks: [TaskItem]

        public init(planID: String, title: String, tasks: [TaskItem]) {
            self.planID = planID
            self.title = title
            self.tasks = tasks
        }
    }

    public enum ConfidenceLevel: String, Codable, Equatable, Sendable {
        case low
        case medium
        case high
        case needsReview
    }

    public struct RecommendationAlternative: Identifiable, Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let prompt: String

        public init(id: String, title: String, prompt: String) {
            self.id = id
            self.title = title
            self.prompt = prompt
        }
    }

    public struct Recommendation: Codable, Equatable, Sendable {
        public let title: String
        public let explanation: String
        public let nextPrompt: String
        public let alternatives: [RecommendationAlternative]
        public let confidenceLevel: ConfidenceLevel?

        public init(title: String, explanation: String, nextPrompt: String, alternatives: [RecommendationAlternative], confidenceLevel: ConfidenceLevel? = nil) {
            self.title = title
            self.explanation = explanation
            self.nextPrompt = nextPrompt
            self.alternatives = alternatives
            self.confidenceLevel = confidenceLevel
        }
    }

    public struct InsightMetric: Codable, Equatable, Sendable {
        public let label: String
        public let value: Double
        public let unit: String?
        public let change: Double?

        public init(label: String, value: Double, unit: String? = nil, change: Double? = nil) {
            self.label = label
            self.value = value
            self.unit = unit
            self.change = change
        }
    }

    public struct Insight: Codable, Equatable, Sendable {
        public let title: String
        public let explanation: String
        public let metrics: [InsightMetric]

        public init(title: String, explanation: String, metrics: [InsightMetric]) {
            self.title = title
            self.explanation = explanation
            self.metrics = metrics
        }
    }

    public struct Code: Codable, Equatable, Sendable {
        public let summary: String
        public let language: String?
        public let filename: String?
        public let code: String

        public init(summary: String, language: String? = nil, filename: String? = nil, code: String) {
            self.summary = summary
            self.language = language
            self.filename = filename
            self.code = code
        }
    }

    public struct ShareDraft: Codable, Equatable, Sendable {
        public let summary: String
        public let title: String?
        public let text: String

        public init(summary: String, title: String? = nil, text: String) {
            self.summary = summary
            self.title = title
            self.text = text
        }
    }

    public enum Content: Equatable, Sendable {
        case scalar(Scalar)
        case searchResults(SearchResults)
        case document(Document)
        case contextMatches(ContextMatches)
        case recordCollection(RecordCollection)
        case mutationReceipt(MutationReceipt)
        case artifactMutation(ArtifactMutation)
        case diff(Diff)
        case taskList(TaskList)
        case recommendation(Recommendation)
        case insight(Insight)
        case code(Code)
        case shareDraft(ShareDraft)
    }

    public let schemaVersion: Int
    public let name: Name
    public let content: Content

    public static func scalar(_ value: Scalar) -> Self { .init(name: .scalar, content: .scalar(value)) }
    public static func searchResults(_ value: SearchResults) -> Self { .init(name: .searchResults, content: .searchResults(value)) }
    public static func document(_ value: Document) -> Self { .init(name: .document, content: .document(value)) }
    public static func contextMatches(_ value: ContextMatches) -> Self { .init(name: .contextMatches, content: .contextMatches(value)) }
    public static func recordCollection(_ value: RecordCollection) -> Self { .init(name: .recordCollection, content: .recordCollection(value)) }
    public static func mutationReceipt(_ value: MutationReceipt) -> Self { .init(name: .mutationReceipt, content: .mutationReceipt(value)) }
    public static func artifactMutation(_ value: ArtifactMutation) -> Self { .init(name: .artifactMutation, content: .artifactMutation(value)) }
    public static func diff(_ value: Diff) -> Self { .init(name: .diff, content: .diff(value)) }
    public static func taskList(_ value: TaskList) -> Self { .init(name: .taskList, content: .taskList(value)) }
    public static func recommendation(_ value: Recommendation) -> Self { .init(name: .recommendation, content: .recommendation(value)) }
    public static func insight(_ value: Insight) -> Self { .init(name: .insight, content: .insight(value)) }
    public static func code(_ value: Code) -> Self { .init(name: .code, content: .code(value)) }
    public static func shareDraft(_ value: ShareDraft) -> Self { .init(name: .shareDraft, content: .shareDraft(value)) }

    public var summary: String {
        switch content {
        case .scalar(let value): value.summary
        case .searchResults(let value): value.summary
        case .document(let value): value.summary
        case .contextMatches(let value): value.summary
        case .recordCollection(let value): value.summary
        case .mutationReceipt(let value): value.summary
        case .artifactMutation(let value): value.summary
        case .diff(let value): value.summary
        case .taskList(let value): value.title
        case .recommendation(let value): value.title
        case .insight(let value): value.title
        case .code(let value): value.summary
        case .shareDraft(let value): value.summary
        }
    }

    private init(name: Name, content: Content) {
        schemaVersion = Self.currentSchemaVersion
        self.name = name
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "Unsupported tool presentation schema version: \(schemaVersion)")
        }
        let name = try container.decode(Name.self, forKey: .name)
        self.schemaVersion = schemaVersion
        self.name = name
        content = switch name {
        case .scalar: .scalar(try container.decode(Scalar.self, forKey: .payload))
        case .searchResults: .searchResults(try container.decode(SearchResults.self, forKey: .payload))
        case .document: .document(try container.decode(Document.self, forKey: .payload))
        case .contextMatches: .contextMatches(try container.decode(ContextMatches.self, forKey: .payload))
        case .recordCollection: .recordCollection(try container.decode(RecordCollection.self, forKey: .payload))
        case .mutationReceipt: .mutationReceipt(try container.decode(MutationReceipt.self, forKey: .payload))
        case .artifactMutation: .artifactMutation(try container.decode(ArtifactMutation.self, forKey: .payload))
        case .diff: .diff(try container.decode(Diff.self, forKey: .payload))
        case .taskList: .taskList(try container.decode(TaskList.self, forKey: .payload))
        case .recommendation: .recommendation(try container.decode(Recommendation.self, forKey: .payload))
        case .insight: .insight(try container.decode(Insight.self, forKey: .payload))
        case .code: .code(try container.decode(Code.self, forKey: .payload))
        case .shareDraft: .shareDraft(try container.decode(ShareDraft.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        switch content {
        case .scalar(let value): try container.encode(value, forKey: .payload)
        case .searchResults(let value): try container.encode(value, forKey: .payload)
        case .document(let value): try container.encode(value, forKey: .payload)
        case .contextMatches(let value): try container.encode(value, forKey: .payload)
        case .recordCollection(let value): try container.encode(value, forKey: .payload)
        case .mutationReceipt(let value): try container.encode(value, forKey: .payload)
        case .artifactMutation(let value): try container.encode(value, forKey: .payload)
        case .diff(let value): try container.encode(value, forKey: .payload)
        case .taskList(let value): try container.encode(value, forKey: .payload)
        case .recommendation(let value): try container.encode(value, forKey: .payload)
        case .insight(let value): try container.encode(value, forKey: .payload)
        case .code(let value): try container.encode(value, forKey: .payload)
        case .shareDraft(let value): try container.encode(value, forKey: .payload)
        }
    }
}

nonisolated public struct FamiliarToolResultEnvelope: Codable, Equatable, Sendable {
    public let modelContent: String
    public let presentation: FamiliarToolPresentationPayload

    public init<T: Encodable>(model: T, presentation: FamiliarToolPresentationPayload) throws {
        let data = try JSONEncoder().encode(model)
        let json = String(decoding: data, as: UTF8.self)
        self.modelContent = FamiliarCanonicalJSON.string(for: json)
        self.presentation = presentation
    }

    public init(canonicalModelJSON: String, presentation: FamiliarToolPresentationPayload) throws {
        guard let data = canonicalModelJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
        else {
            throw FamiliarToolResultContractError.invalidModelJSON
        }
        self.modelContent = FamiliarCanonicalJSON.string(for: canonicalModelJSON)
        self.presentation = presentation
    }

    public var summary: String { presentation.summary }
}

nonisolated public enum FamiliarToolResultContractError: Error, Sendable {
    case invalidModelJSON
}

nonisolated public struct FamiliarToolFailure: Codable, Equatable, Sendable {
    public let code: String
    public let retryable: Bool
    public let message: String

    public init(code: String, retryable: Bool, message: String) {
        self.code = code
        self.retryable = retryable
        self.message = message
    }
}

nonisolated public enum FamiliarApprovalFieldType: String, Codable, Sendable {
    case text
    case date
    case boolean
    case number
    case url
    case sensitive
}

nonisolated public struct FamiliarApprovalField: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let type: FamiliarApprovalFieldType
    public let value: String

    public init(id: String, label: String, type: FamiliarApprovalFieldType, value: String) {
        self.id = id
        self.label = label
        self.type = type
        self.value = value
    }

    public var formattedValue: String {
        switch type {
        case .boolean:
            return value.lowercased() == "true" ? String(localized: "common.yes") : String(localized: "common.no")
        case .sensitive:
            return String(repeating: "•", count: min(max(value.count, 4), 12))
        case .text, .date, .number, .url:
            return value
        }
    }
}

nonisolated public enum FamiliarApprovalUndoPolicy: String, Codable, Sendable {
    case unavailable
    case currentSession
    case durable
}

nonisolated enum FamiliarCapabilityRequirement: String, Codable, Hashable, Sendable {
    case calendarFullAccess
    case remindersFullAccess
    case contactsRead
    case locationWhenInUse
}

nonisolated enum FamiliarCapabilityAvailability: Equatable, Sendable {
    case available
    case requestable
    case unavailable(reason: String)
}

nonisolated struct FamiliarToolContext: Sendable {
    struct Resource: Sendable {
        let id: UUID
        let versionID: UUID
        let version: Int
        let displayName: String
        let filename: String
        let mimeType: String
        let contentHash: String
        let extractedText: String
    }

    struct Attachment: Sendable {
        let id: UUID
        let kind: FamiliarAttachmentKind
        let filename: String
        let mimeType: String
        let relativePath: String
        let extractedText: String
        let byteSize: Int64
    }

    let runID: String
    let toolCallID: String
    let projectID: UUID?
    let conversationID: UUID?
    let workspaceID: FamiliarWorkspaceID?
    let resources: [Resource]
    let attachments: [Attachment]

    init(
        runID: String = "standalone",
        toolCallID: String = UUID().uuidString,
        projectID: UUID? = nil,
        conversationID: UUID? = nil,
        workspaceID: FamiliarWorkspaceID? = nil,
        resources: [Resource] = [],
        attachments: [Attachment] = []
    ) {
        self.runID = runID
        self.toolCallID = toolCallID
        self.projectID = projectID
        self.conversationID = conversationID
        self.workspaceID = workspaceID
        self.resources = resources
        self.attachments = attachments
    }

    var idempotencyKey: String { runID + ":" + toolCallID }
}

nonisolated struct FamiliarToolExecutionResult: Sendable {
    let envelope: FamiliarToolResultEnvelope
    let artifactIdentifier: String?
    let sources: [FamiliarSource]
    let webCaptures: [FamiliarWebCapture]
    let artifact: FamiliarArtifactDescriptor?

    init(envelope: FamiliarToolResultEnvelope, artifactIdentifier: String? = nil, sources: [FamiliarSource] = [], webCaptures: [FamiliarWebCapture] = [], artifact: FamiliarArtifactDescriptor? = nil) {
        self.envelope = envelope
        self.artifactIdentifier = artifactIdentifier
        self.sources = sources
        self.webCaptures = webCaptures
        self.artifact = artifact
    }

    var modelContent: String { envelope.modelContent }
    var summary: String { envelope.summary }
}

typealias FamiliarUndoAction = @Sendable () async throws -> FamiliarToolExecutionResult

nonisolated struct FamiliarCommittedAction: Sendable {
    let result: FamiliarToolExecutionResult
    let undo: FamiliarUndoAction?

    init(result: FamiliarToolExecutionResult, undo: FamiliarUndoAction? = nil) {
        self.result = result
        self.undo = undo
    }
}

nonisolated struct FamiliarActionProposal: Sendable {
    let title: String
    let fields: [FamiliarApprovalField]
    let target: String?
    let targetKey: String
    let effect: FamiliarToolEffect
    let risk: FamiliarToolRisk
    let consequence: String
    let undoPolicy: FamiliarApprovalUndoPolicy
    let idempotencyKey: String
    let commit: @Sendable () async throws -> FamiliarCommittedAction

    init(title: String, fields: [FamiliarApprovalField], target: String?, targetKey: String? = nil, effect: FamiliarToolEffect, risk: FamiliarToolRisk, consequence: String, undoPolicy: FamiliarApprovalUndoPolicy, idempotencyKey: String, commit: @escaping @Sendable () async throws -> FamiliarCommittedAction) {
        self.title = title
        self.fields = fields
        self.target = target
        self.targetKey = targetKey ?? target ?? "default"
        self.effect = effect
        self.risk = risk
        self.consequence = consequence
        self.undoPolicy = undoPolicy
        self.idempotencyKey = idempotencyKey
        self.commit = commit
    }
}

nonisolated public struct FamiliarClarificationOption: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

nonisolated struct FamiliarClarificationProposal: Sendable {
    let question: String
    let options: [FamiliarClarificationOption]
    let allowCustom: Bool
}

nonisolated enum FamiliarToolOutcome: Sendable {
    case result(FamiliarToolExecutionResult)
    case action(FamiliarActionProposal)
    case clarification(FamiliarClarificationProposal)
}

nonisolated protocol FamiliarCapabilityProviding: Sendable {
    func availability(for requirement: FamiliarCapabilityRequirement) async -> FamiliarCapabilityAvailability
    func request(_ requirement: FamiliarCapabilityRequirement) async throws
}

nonisolated protocol FamiliarTool: Sendable {
    associatedtype Input: Decodable & Sendable

    var manifest: FamiliarToolManifest { get }

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome
}

nonisolated struct AnyFamiliarTool: Sendable {
    let manifest: FamiliarToolManifest
    private let executeClosure: @Sendable (Data, FamiliarToolContext) async throws -> FamiliarToolOutcome

    init<T: FamiliarTool>(_ tool: T) {
        manifest = tool.manifest
        executeClosure = { data, context in
            let input = try JSONDecoder().decode(T.Input.self, from: data)
            return try await tool.execute(input, context: context)
        }
    }

    func execute(arguments: String, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let normalized = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = (normalized.isEmpty ? "{}" : normalized).data(using: .utf8) else {
            throw FamiliarToolRegistryError.invalidArguments(manifest.name)
        }
        do {
            return try await executeClosure(data, context)
        } catch let error as DecodingError {
            throw FamiliarToolRegistryError.argumentDecodingFailed(
                tool: manifest.name,
                reason: error.localizedDescription
            )
        }
    }
}

nonisolated enum FamiliarToolRegistryError: LocalizedError, Sendable {
    case duplicateTool(String)
    case toolNotFound(String)
    case invalidArguments(String)
    case argumentDecodingFailed(tool: String, reason: String)
    case capabilityUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .duplicateTool(let name): String(format: String(localized: "error.tool.duplicate"), name)
        case .toolNotFound(let name): String(format: String(localized: "error.tool.not_found"), name)
        case .invalidArguments(let name): String(format: String(localized: "error.tool.invalid_arguments"), name)
        case .argumentDecodingFailed(let tool, let reason):
            String(format: String(localized: "error.tool.decoding"), tool, reason)
        case .capabilityUnavailable(let reason): reason
        }
    }
}

actor FamiliarToolRegistry {
    private let toolsByName: [String: AnyFamiliarTool]
    private let capabilities: (any FamiliarCapabilityProviding)?

    init(tools: [AnyFamiliarTool], capabilities: (any FamiliarCapabilityProviding)? = nil) throws {
        var values: [String: AnyFamiliarTool] = [:]
        for tool in tools {
            guard values[tool.manifest.name] == nil else {
                throw FamiliarToolRegistryError.duplicateTool(tool.manifest.name)
            }
            values[tool.manifest.name] = tool
        }
        toolsByName = values
        self.capabilities = capabilities
    }

    func manifests() async -> [FamiliarToolManifest] {
        var result: [FamiliarToolManifest] = []
        for manifest in snapshot() {
            guard case .unavailable = await availability(for: manifest) else {
                result.append(manifest)
                continue
            }
        }
        return result
    }

    func snapshot() -> [FamiliarToolManifest] {
        toolsByName.values.map(\.manifest).sorted {
            if $0.executionClass.preferenceRank != $1.executionClass.preferenceRank {
                return $0.executionClass.preferenceRank < $1.executionClass.preferenceRank
            }
            return $0.name < $1.name
        }
    }

    func manifest(named name: String) throws -> FamiliarToolManifest {
        guard let tool = toolsByName[name] else { throw FamiliarToolRegistryError.toolNotFound(name) }
        return tool.manifest
    }

    func availability(for manifest: FamiliarToolManifest) async -> FamiliarCapabilityAvailability {
        guard let capabilities else {
            return manifest.requirements.isEmpty ? .available : .unavailable(reason: "设备能力服务不可用。")
        }
        var needsRequest = false
        for requirement in manifest.requirements {
            switch await capabilities.availability(for: requirement) {
            case .available: continue
            case .requestable: needsRequest = true
            case .unavailable(let reason): return .unavailable(reason: reason)
            }
        }
        return needsRequest ? .requestable : .available
    }

    func prepareCapabilities(for manifest: FamiliarToolManifest) async throws {
        guard let capabilities else {
            guard manifest.requirements.isEmpty else {
                throw FamiliarToolRegistryError.capabilityUnavailable("设备能力服务不可用。")
            }
            return
        }
        for requirement in manifest.requirements {
            switch await capabilities.availability(for: requirement) {
            case .available: continue
            case .requestable: try await capabilities.request(requirement)
            case .unavailable(let reason): throw FamiliarToolRegistryError.capabilityUnavailable(reason)
            }
        }
    }

    func execute(
        name: String,
        arguments: String,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome {
        guard let tool = toolsByName[name] else { throw FamiliarToolRegistryError.toolNotFound(name) }
        return try await tool.execute(arguments: arguments, context: context)
    }
}
