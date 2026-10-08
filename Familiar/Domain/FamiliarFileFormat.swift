import Foundation

nonisolated enum FamiliarFileFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case markdown
    case plainText
    case docx
    case pdf
    case xlsx
    case html

    var filenameExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .docx: "docx"
        case .pdf: "pdf"
        case .xlsx: "xlsx"
        case .html: "html"
        }
    }

    var mimeType: String {
        switch self {
        case .markdown: "text/markdown"
        case .plainText: "text/plain"
        case .docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .pdf: "application/pdf"
        case .xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .html: "text/html"
        }
    }

    var utiIdentifier: String {
        switch self {
        case .markdown: "net.daringfireball.markdown"
        case .plainText: "public.plain-text"
        case .docx: "org.openxmlformats.wordprocessingml.document"
        case .pdf: "com.adobe.pdf"
        case .xlsx: "org.openxmlformats.spreadsheetml.sheet"
        case .html: "public.html"
        }
    }
}
nonisolated enum FamiliarFileSource: String, Codable, Sendable { case generated, webCapture, projectResource }
