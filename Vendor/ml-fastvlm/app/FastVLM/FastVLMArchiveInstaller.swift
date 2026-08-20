import Foundation
import ZIPFoundation

public enum FastVLMArchiveInstaller {
    public static func extract(archiveURL: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let root = destination.standardizedFileURL.path + "/"
        for entry in archive {
            let output = destination.appendingPathComponent(entry.path).standardizedFileURL
            guard output.path.hasPrefix(root) else { throw CocoaError(.fileReadInvalidFileName) }
            _ = try archive.extract(entry, to: output)
        }
    }
}
