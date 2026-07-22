import Foundation

enum ConfigStore {
    static let fileName = "cloudbox.local.json"

    static var fileURL: URL {
        projectDirectory.appendingPathComponent(fileName)
    }

    /// Prefer the Swift package root (directory with `Package.swift`), falling back to cwd.
    static var projectDirectory: URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if isProjectRoot(cwd) { return cwd }

        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent())
        }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())
        candidates.append(cwd)

        for start in candidates {
            var dir = start.standardizedFileURL
            for _ in 0..<10 {
                if isProjectRoot(dir) { return dir }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return cwd
    }

    static func save(_ configuration: CloudConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    static func load() -> CloudConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CloudConfiguration.self, from: data)
    }

    private static func isProjectRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
    }
}
