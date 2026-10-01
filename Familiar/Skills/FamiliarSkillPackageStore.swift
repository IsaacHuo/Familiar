import Foundation
import SwiftData
import ZIPFoundation
import Yams

nonisolated struct FamiliarSkillPackageStore: Sendable {
    struct Manifest: Codable, Sendable {
        let document: FamiliarSkillDocument
        let files: [String: String]
        let source: String?
    }
    final class Prepared: @unchecked Sendable {
        let root: URL
        let manifest: Manifest
        let hash: String
        init(root: URL, manifest: Manifest, hash: String) { self.root = root; self.manifest = manifest; self.hash = hash }
        deinit { try? FileManager.default.removeItem(at: root) }
    }
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar/SkillPackages", isDirectory: true)
    }
    static let maximumBytes = 100 * 1_024 * 1_024
    static let maximumFiles = 2_048

    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }
    private func directory(hash: String) throws -> URL {
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw FamiliarSkillParserError.invalid }
        return root.appendingPathComponent(hash, isDirectory: true)
    }
    func manifest(hash: String) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory(hash: hash).appendingPathComponent("manifest.json")))
    }
    func resource(hash: String, path: String) throws -> URL {
        guard Self.safePath(path), let expected = try manifest(hash: hash).files[path] else { throw FamiliarSkillParserError.invalid }
        let base = try directory(hash: hash).appendingPathComponent("content", isDirectory: true)
        let file = base.appendingPathComponent(path)
        guard file.resolvingSymlinksInPath().pathComponents.starts(with: base.resolvingSymlinksInPath().pathComponents),
              try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]).isRegularFile == true,
              try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try FamiliarHash.sha256(contentsOf: file) == expected else { throw FamiliarSkillParserError.invalid }
        return file
    }
    func prepare(url: URL, source: String? = nil, subpath: String? = nil) throws -> Prepared {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("skill-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var retained = false
        defer { if !retained { try? fm.removeItem(at: staging) } }
        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw FamiliarSkillParserError.invalid }
        if values.isDirectory == true {
            try copyChecked(from: url, to: extracted)
        } else if url.pathExtension.lowercased() == "zip" {
            let archive = try Archive(url: url, accessMode: .read)
            var count = 0
            var size: UInt64 = 0
            for entry in archive {
                let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                guard Self.safePath(path), entry.type != .symlink else { throw FamiliarSkillParserError.invalid }
                count += 1; size += entry.uncompressedSize
                guard count <= Self.maximumFiles, size <= Self.maximumBytes else { throw FamiliarSkillParserError.tooLarge }
                let destination = extracted.appendingPathComponent(path, isDirectory: entry.type == .directory)
                guard !fm.fileExists(atPath: destination.path) || entry.type == .directory else { throw FamiliarSkillParserError.invalid }
                _ = try archive.extract(entry, to: destination)
            }
        } else {
            guard url.lastPathComponent.lowercased() == "skill.md" else { throw FamiliarSkillParserError.unsupported }
            try fm.copyItem(at: url, to: extracted.appendingPathComponent("SKILL.md"))
        }
        var packageRoot = extracted
        if !fm.fileExists(atPath: packageRoot.appendingPathComponent("SKILL.md").path) {
            let children = try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            if children.count == 1, try children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { packageRoot = children[0] }
        }
        if let subpath, !subpath.isEmpty {
            guard Self.safePath(subpath) else { throw FamiliarSkillParserError.invalid }
            packageRoot.appendPathComponent(subpath, isDirectory: true)
        }
        let content = staging.appendingPathComponent("content", isDirectory: true)
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        let files = try copyChecked(from: packageRoot, to: content)
        let skillURL = content.appendingPathComponent("SKILL.md")
        guard let size = try? skillURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 256 * 1_024 else { throw FamiliarSkillParserError.tooLarge }
        let document = try Self.parse(String(contentsOf: skillURL, encoding: .utf8))
        let manifest = Manifest(document: document, files: files, source: source)
        let identity = files.keys.sorted().map { "\($0)\0\(files[$0]!)" }.joined(separator: "\n")
        let hash = FamiliarHash.sha256(identity)
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try fm.removeItem(at: extracted)
        retained = true
        return Prepared(root: staging, manifest: manifest, hash: hash)
    }
    @discardableResult
    private func copyChecked(from source: URL, to destination: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else { throw FamiliarSkillParserError.invalid }
        var files: [String: String] = [:]
        var bytes = 0
        var count = 0
        for case let file as URL in enumerator {
            count += 1
            let parts = file.pathComponents.dropFirst(source.pathComponents.count)
            let path = parts.joined(separator: "/")
            let info = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard Self.safePath(path), info.isSymbolicLink != true else { throw FamiliarSkillParserError.invalid }
            bytes += info.fileSize ?? 0
            guard count <= Self.maximumFiles, bytes <= Self.maximumBytes else { throw FamiliarSkillParserError.tooLarge }
            let target = destination.appendingPathComponent(path, isDirectory: info.isDirectory == true)
            if info.isDirectory == true { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                guard info.isRegularFile == true else { throw FamiliarSkillParserError.invalid }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: target)
                files[path] = try FamiliarHash.sha256(contentsOf: target)
            }
        }
        return files
    }
    private static func parse(_ text: String) throws -> FamiliarSkillDocument {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"),
              let metadata = try Yams.load(yaml: lines[1..<end].joined(separator: "\n")) as? [String: Any],
              let name = metadata["name"] as? String, let description = metadata["description"] as? String,
              name.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
              !description.isEmpty else { throw FamiliarSkillParserError.invalid }
        let instructions = lines[(end + 1)...].joined(separator: "\n")
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.count <= 32_000 else { throw FamiliarSkillParserError.emptyInstructions }
        let tools = (metadata["allowed-tools"] as? [String]) ?? (metadata["allowed-tools"] as? String)?.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init) ?? []
        return .init(format: "familiar.skill", formatVersion: 1, id: name,
                     version: metadata["version"] as? String ?? "1.0.0", name: name,
                     description: String(description.prefix(2_000)), instructions: instructions, allowedTools: tools, examples: [])
    }
    func commit(_ prepared: Prepared) throws -> FamiliarSkillSnapshot {
        let fm = FileManager.default
        let target = try directory(hash: prepared.hash)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: target.path) {
            let staging = root.appendingPathComponent(".\(UUID().uuidString)")
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: prepared.root, to: staging)
            try fm.moveItem(at: staging, to: target)
        }
        let doc = prepared.manifest.document
        return .init(stableID: doc.id, version: doc.version, name: doc.name, contentHash: prepared.hash,
                     instructions: doc.instructions, allowedTools: doc.allowedTools,
                     resources: prepared.manifest.files.keys.sorted())
    }
    @MainActor
    func persistInstallation(_ snapshot: FamiliarSkillSnapshot, projectID: UUID? = nil, context: ModelContext) throws {
        let package = try manifest(hash: snapshot.contentHash)
        do {
            let skill = try FamiliarSkillService().stageInstallation(package.document, in: context)
            skill.contentHash = snapshot.contentHash
            if let projectID { try FamiliarProjectService().stageSkill(skill.id, enabled: true, projectID: projectID, in: context) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

nonisolated struct FamiliarSkillInstallTool: FamiliarTool {
    struct Input: Decodable, Sendable { let url: String }
    let store = FamiliarSkillPackageStore()
    let manifest = FamiliarToolManifest(name: "skill_install", title: "Install Project Skill",
        description: "Propose installing a public GitHub repository/subdirectory or HTTPS Skill ZIP into this Project. Approval is required. No installation scripts run and no permissions are granted.",
        parameters: .object(["url": .string("Public GitHub repo/tree URL or HTTPS ZIP URL")], required: ["url"]),
        effect: .reversibleWrite, risk: .sensitive, supportsParallelism: false, requiredScopes: ["project"])
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarSkillServiceError.unavailable }
        var url = try FamiliarWebURLPolicy.normalize(input.url)
        guard url.scheme == "https" else { throw FamiliarSkillParserError.unsupported }
        let http = FamiliarRestrictedHTTPClient()
        var subpath: String?
        if url.host == "github.com" {
            let pieces = url.path.split(separator: "/").map(String.init)
            guard pieces.count >= 2 else { throw FamiliarSkillParserError.invalid }
            let repo = pieces[0] + "/" + pieces[1].replacingOccurrences(of: ".git", with: "")
            var ref = "HEAD"
            if pieces.count > 2 {
                guard pieces.count >= 4, pieces[2] == "tree" else { throw FamiliarSkillParserError.unsupported }
                ref = pieces[3]
                subpath = pieces.dropFirst(4).joined(separator: "/")
            }
            let commitResponse = try await http.get(URL(string: "https://api.github.com/repos/\(repo)/commits/\(ref)")!)
            guard commitResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: commitResponse.body) as? [String: Any], let sha = json["sha"] as? String,
                  sha.count == 40, sha.allSatisfy({ $0.isHexDigit }) else { throw FamiliarSkillParserError.invalid }
            url = URL(string: "https://codeload.github.com/\(repo)/zip/\(sha)")!
        }
        let response = try await http.get(url, bodyLimit: 25 * 1_024 * 1_024, timeout: .seconds(60))
        guard response.statusCode == 200 else { throw FamiliarSkillParserError.invalid }
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        try response.body.write(to: archive, options: .atomic)
        let prepared = try store.prepare(url: archive, source: response.finalURL.absoluteString, subpath: subpath)
        return .action(.init(title: "安装项目技能", fields: [
            .init(id: "source", label: "Source", type: .url, value: response.finalURL.absoluteString),
            .init(id: "name", label: "Skill", type: .text, value: prepared.manifest.document.name),
            .init(id: "hash", label: "SHA-256", type: .text, value: prepared.hash),
            .init(id: "resources", label: "Resources", type: .text, value: prepared.manifest.files.keys.sorted().joined(separator: "\n")),
            .init(id: "tools", label: "Tool scope", type: .text, value: prepared.manifest.document.allowedTools.joined(separator: ", "))
        ], target: projectID.uuidString, targetKey: "skill:\(projectID):\(prepared.hash)", effect: .reversibleWrite, risk: .sensitive,
           consequence: "将安装已检查的技能包并绑定当前项目。安装不会执行脚本或授予额外权限。", undoPolicy: .unavailable,
           idempotencyKey: context.idempotencyKey, allowedAuthorizationDurations: [.once], commit: {
            let snapshot = try store.commit(prepared)
            return .init(result: .init(envelope: try .init(model: snapshot,
                presentation: .scalar(.init(summary: "已安装项目技能", label: "Skill", value: snapshot.name))), installedSkill: snapshot))
        }))
    }
}
