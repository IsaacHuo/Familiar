import Foundation
import UniformTypeIdentifiers

nonisolated enum FamiliarFileCategory: String, CaseIterable, Identifiable {
    case all, image, pdf, document, spreadsheet, presentation, text, other
    var id: String { rawValue }
    var title: String { String(localized: String.LocalizationValue("files.type." + rawValue)) }
    static func classify(filename: String, mimeType: String) -> Self {
        if UTType(mimeType: mimeType)?.conforms(to: .image) == true || UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)?.conforms(to: .image) == true { return .image }
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": return .pdf
        case "doc", "docx", "odt", "rtf", "epub": return .document
        case "xls", "xlsx", "ods", "csv", "tsv": return .spreadsheet
        case "ppt", "pptx", "odp": return .presentation
        case "txt", "md", "markdown", "html", "htm", "json", "xml", "yaml", "yml", "swift", "py", "js", "ts", "css", "sh", "sql": return .text
        default: return UTType(mimeType: mimeType)?.conforms(to: .text) == true ? .text : .other
        }
    }
}

nonisolated enum FamiliarFileSort: String, CaseIterable, Identifiable {
    case recent, oldest, name, size
    var id: String { rawValue }
    var title: String { String(localized: String.LocalizationValue("files.sort." + rawValue)) }
    var groupsDates: Bool { self == .recent || self == .oldest }
}

extension FamiliarFileOrigin {
    var title: String { String(localized: String.LocalizationValue("files.origin." + rawValue)) }
}
