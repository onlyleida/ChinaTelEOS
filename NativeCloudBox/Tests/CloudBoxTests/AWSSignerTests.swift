import XCTest
@testable import CloudBox

final class AWSSignerTests: XCTestCase {
    func testSHA256() {
        XCTAssertEqual(AWSSigner.sha256(Data("hello".utf8)), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testFolderExpansionPreservesRootName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try CloudViewModel.expand(root, remotePrefix: "docs/")
        XCTAssertEqual(entries.map(\.remoteKey), ["docs/\(root.lastPathComponent)/inside/a.txt"])
    }
}
