import AnyDocBridge
import Foundation

nonisolated struct FamiliarAnyDocConversion: Sendable {
    let markdown: String
    let formatID: String
    let engineVersion: String
    let usedOCR: Bool
}

nonisolated enum FamiliarAnyDocError: LocalizedError, Sendable {
    case unsupported(String)
    case malformed(String)
    case encrypted
    case resourceLimit(String)
    case missingPart(String)
    case inputOutput(String)
    case bridgeFailure

    var errorDescription: String? {
        switch self {
        case .unsupported:
            String(localized: "anydoc.error.unsupported")
        case .malformed:
            String(localized: "anydoc.error.malformed")
        case .encrypted:
            String(localized: "anydoc.error.encrypted")
        case .resourceLimit:
            String(localized: "anydoc.error.resource_limit")
        case .missingPart:
            String(localized: "anydoc.error.missing_part")
        case .inputOutput:
            String(localized: "anydoc.error.io")
        case .bridgeFailure:
            String(localized: "anydoc.error.bridge")
        }
    }

    var diagnosticDetail: String? {
        switch self {
        case .unsupported(let detail), .malformed(let detail), .resourceLimit(let detail),
             .missingPart(let detail), .inputOutput(let detail):
            detail
        case .encrypted, .bridgeFailure:
            nil
        }
    }
}

nonisolated enum FamiliarAnyDocService {
    static let engineName = "AnyDoc"
    static let supportedExtensions: Set<String> = [
        "doc", "docx", "docm",
        "ppt", "pps", "pot", "pptx", "pptm", "ppsx", "ppsm",
        "xls", "xlsx", "xlsm", "xlsb",
        "odt", "ods", "odp",
        "rtf", "epub", "csv", "pdf",
        "txt", "md", "markdown"
    ]

    static var engineVersion: String {
        String(cString: familiar_anydoc_version())
    }

    static func convert(data: Data, filename: String) throws -> FamiliarAnyDocConversion {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw FamiliarAnyDocError.unsupported(fileExtension)
        }

        let result = fileExtension.withCString { extensionPointer in
            data.withUnsafeBytes { rawBuffer in
                familiar_anydoc_convert(
                    rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    rawBuffer.count,
                    extensionPointer
                )
            }
        }
        guard let result else { throw FamiliarAnyDocError.bridgeFailure }
        defer { familiar_anydoc_result_free(result) }

        let errorCode = string(from: familiar_anydoc_error_code(result))
        if !errorCode.isEmpty {
            let detail = string(from: familiar_anydoc_error_message(result))
            throw mappedError(code: errorCode, detail: detail)
        }

        let length = familiar_anydoc_markdown_length(result)
        guard length > 0,
              let bytes = familiar_anydoc_markdown_bytes(result),
              let markdown = String(bytes: UnsafeBufferPointer(start: bytes, count: length), encoding: .utf8),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw FamiliarAnyDocError.bridgeFailure
        }

        return FamiliarAnyDocConversion(
            markdown: markdown,
            formatID: string(from: familiar_anydoc_format(result)),
            engineVersion: engineVersion,
            usedOCR: false
        )
    }

    private static func string(from pointer: UnsafePointer<CChar>?) -> String {
        pointer.map(String.init(cString:)) ?? ""
    }

    private static func mappedError(code: String, detail: String) -> FamiliarAnyDocError {
        switch code {
        case "unsupported": .unsupported(detail)
        case "malformed": .malformed(detail)
        case "encrypted": .encrypted
        case "resourceLimit": .resourceLimit(detail)
        case "missingPart": .missingPart(detail)
        case "io": .inputOutput(detail)
        default: .bridgeFailure
        }
    }
}
