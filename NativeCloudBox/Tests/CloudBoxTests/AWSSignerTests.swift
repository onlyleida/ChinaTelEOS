import XCTest
@testable import CloudBox

final class AWSSignerTests: XCTestCase {
    func testSHA256() {
        XCTAssertEqual(AWSSigner.sha256(Data("hello".utf8)), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testSignedRequestIncludesACLHeader() {
        let configuration = CloudConfiguration(
            endpoint: "https://oos-cn.ctyunapi.cn",
            region: "cn-shanghai",
            bucket: "demo",
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        )
        let url = URL(string: "https://oos-cn.ctyunapi.cn/demo/file.txt")!
        let request = AWSSigner.signedRequest(
            url: url,
            method: "PUT",
            bodyHash: AWSSigner.sha256(Data()),
            configuration: configuration,
            extraHeaders: ["x-amz-acl": ObjectAcl.publicRead.headerValue],
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-acl"), "public-read")
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        XCTAssertTrue(authorization.contains("SignedHeaders=host;x-amz-acl;x-amz-content-sha256;x-amz-date"))
    }

    func testFolderExpansionPreservesRootName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try CloudViewModel.expand(root, remotePrefix: "docs/", acl: .publicRead)
        XCTAssertEqual(entries.map(\.remoteKey), ["docs/\(root.lastPathComponent)/inside/a.txt"])
        XCTAssertEqual(entries.map(\.acl), [.publicRead])
    }
}
