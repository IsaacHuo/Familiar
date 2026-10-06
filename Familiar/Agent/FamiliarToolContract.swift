import Foundation

/// One output envelope contract for every adapter. Typed tools own their model payload;
/// the boundary validates size, JSON shape and the supported presentation version.
nonisolated struct FamiliarToolOutputContract: Codable, Equatable, Sendable {
    let maximumCharacters: Int
    let presentationSchemaVersion: Int

    init(maximumCharacters: Int = 48_000, presentationSchemaVersion: Int = FamiliarToolPresentationPayload.currentSchemaVersion) {
        self.maximumCharacters = maximumCharacters
        self.presentationSchemaVersion = presentationSchemaVersion
    }

    func validate(_ result: FamiliarToolExecutionResult) throws {
        guard result.modelContent.count <= maximumCharacters else { throw FamiliarAgentError.toolResultTooLarge }
        guard result.envelope.presentation.schemaVersion == presentationSchemaVersion,
              let object = try? JSONSerialization.jsonObject(with: Data(result.modelContent.utf8)),
              object is [String: Any] || object is [Any] else { throw FamiliarToolDeclarationError.invalidOutput }
    }
}

nonisolated extension FamiliarToolManifest {
    var resultContract: FamiliarToolOutputContract { outputContract ?? .init() }

    func validateDeclaration() throws {
        guard !id.isEmpty, !version.isEmpty, !name.isEmpty, name.count <= 64,
              name.unicodeScalars.allSatisfy({ scalar in
                  (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                      || (48...57).contains(scalar.value) || scalar == "_" || scalar == "-"
              }), parameters.type == .object, payloadLimit > 0, payloadLimit <= 48_000,
              (maximumExecutionDuration.map { $0.isFinite && $0 > 0 } ?? true),
              !supportsParallelism || effect == .read,
              resultContract.maximumCharacters > 0, resultContract.maximumCharacters <= 48_000,
              resultContract.presentationSchemaVersion == FamiliarToolPresentationPayload.currentSchemaVersion
        else { throw FamiliarToolDeclarationError.invalidManifest(name) }
        let required = parameters.required ?? []
        guard Set(required).count == required.count,
              Set(required).isSubset(of: Set(parameters.properties?.keys.map { $0 } ?? []))
        else { throw FamiliarToolDeclarationError.invalidManifest(name) }
    }
}

nonisolated enum FamiliarToolDeclarationError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case invalidManifest(String), invalidOutput, invalidOutcome
    var code: String {
        switch self {
        case .invalidManifest: "tool_invalid_declaration"
        case .invalidOutput: "tool_invalid_output"
        case .invalidOutcome: "tool_effect_contract_mismatch"
        }
    }
    var isRetryable: Bool { false }
    var errorDescription: String? {
        switch self {
        case .invalidManifest(let name): "Invalid tool declaration: " + name
        case .invalidOutput: "The tool returned an unsupported output envelope."
        case .invalidOutcome: "The tool outcome does not match its declared effect."
        }
    }
}
