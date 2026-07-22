import Foundation

final class CloudClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: CloudConfiguration
    private var progressHandlers: [Int: @Sendable (Int64, Int64) -> Void] = [:]
    private let lock = NSLock()
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(configuration: CloudConfiguration) { self.configuration = configuration }

    func list(prefix: String) async throws -> [CloudItem] {
        let url = try makeURL(query: ["list-type": "2", "delimiter": "/", "prefix": prefix])
        let request = AWSSigner.signedRequest(url: url, method: "GET", bodyHash: AWSSigner.sha256(Data()), configuration: configuration)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return ListParser(prefix: prefix).parse(data)
    }

    func createFolder(key: String) async throws {
        try await put(data: Data(), key: key.hasSuffix("/") ? key : key + "/")
    }

    // URLSession's async upload API exposes reliable byte progress through this delegate.
    func uploadFile(file: URL, key: String, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let hash = try AWSSigner.fileHash(file)
        let url = try makeURL(key: key)
        var request = AWSSigner.signedRequest(url: url, method: "PUT", bodyHash: hash, configuration: configuration)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let relay = UploadRelay()
        let task = session.uploadTask(with: request, fromFile: file) { data, response, error in
            if let error { relay.finish(.failure(error)); return }
            do {
                try self.validate(response, data: data ?? Data())
                relay.finish(.success(()))
            } catch { relay.finish(.failure(error)) }
        }
        lock.withLock { progressHandlers[task.taskIdentifier] = progress }
        task.resume()
        try await withTaskCancellationHandler(operation: { try await relay.value() }, onCancel: { task.cancel() })
        _ = lock.withLock { progressHandlers.removeValue(forKey: task.taskIdentifier) }
    }

    func delete(item: CloudItem) async throws {
        if item.isFolder {
            let objects = try await allObjectKeys(prefix: item.key)
            for key in objects { try await deleteObject(key: key) }
        } else {
            try await deleteObject(key: item.key)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let handler = lock.withLock { progressHandlers[task.taskIdentifier] }
        handler?(totalBytesSent, totalBytesExpectedToSend)
    }

    private func put(data: Data, key: String) async throws {
        let url = try makeURL(key: key)
        var request = AWSSigner.signedRequest(url: url, method: "PUT", bodyHash: AWSSigner.sha256(data), configuration: configuration)
        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        try validate(response, data: responseData)
    }

    private func deleteObject(key: String) async throws {
        let url = try makeURL(key: key)
        let request = AWSSigner.signedRequest(url: url, method: "DELETE", bodyHash: AWSSigner.sha256(Data()), configuration: configuration)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    private func allObjectKeys(prefix: String) async throws -> [String] {
        var keys: [String] = []
        var token: String?
        repeat {
            var query = ["list-type": "2", "prefix": prefix]
            if let token { query["continuation-token"] = token }
            let url = try makeURL(query: query)
            let request = AWSSigner.signedRequest(url: url, method: "GET", bodyHash: AWSSigner.sha256(Data()), configuration: configuration)
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data)
            let parser = ListParser(prefix: "", includeOnlyKeys: true)
            keys.append(contentsOf: parser.parse(data).map(\.key))
            token = parser.nextContinuationToken
        } while token != nil
        return keys
    }

    private func makeURL(key: String = "", query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(string: configuration.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { throw CloudError.invalidConfiguration }
        let objectPath = ([configuration.bucket] + (key.isEmpty ? [] : key.split(separator: "/", omittingEmptySubsequences: false).map(String.init))).joined(separator: "/")
        components.path = "/" + objectPath
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw CloudError.invalidConfiguration }
        return url
    }

    private func validate(_ response: URLResponse?, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = ErrorParser().parse(data)
            throw CloudError.server(status: http.statusCode, message: parsed.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : parsed)
        }
    }
}

private final class UploadRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    func finish(_ result: Result<Void, Error>) { lock.withLock { self.result = result; continuation?.resume(with: result); continuation = nil } }
    func value() async throws { try await withCheckedThrowingContinuation { c in lock.withLock { if let result { c.resume(with: result) } else { continuation = c } } } }
}

private final class ListParser: NSObject, XMLParserDelegate {
    private let prefix: String
    private let includeOnlyKeys: Bool
    private var items: [CloudItem] = []
    private var text = "", key = "", size: Int64 = 0, date: Date?
    private var insideContents = false
    private(set) var nextContinuationToken: String?

    init(prefix: String, includeOnlyKeys: Bool = false) { self.prefix = prefix; self.includeOnlyKeys = includeOnlyKeys }
    func parse(_ data: Data) -> [CloudItem] { let parser = XMLParser(data: data); parser.delegate = self; parser.parse(); return items.sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) { text = ""; if elementName == "Contents" { insideContents = true; key = ""; size = 0; date = nil } }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Prefix", !insideContents, text != prefix, !includeOnlyKeys {
            let name = String(text.dropFirst(prefix.count).dropLast())
            if !name.isEmpty { items.append(CloudItem(key: text, name: name, isFolder: true, size: 0, modifiedAt: nil)) }
        } else if insideContents && elementName == "Key" { key = text }
        else if insideContents && elementName == "Size" { size = Int64(text) ?? 0 }
        else if insideContents && elementName == "LastModified" { date = ISO8601DateFormatter().date(from: text) }
        else if elementName == "Contents" {
            insideContents = false
            let name = prefix.isEmpty ? key : String(key.dropFirst(prefix.count))
            if (includeOnlyKeys || !name.isEmpty) && (includeOnlyKeys || !name.contains("/")) { items.append(CloudItem(key: key, name: name, isFolder: key.hasSuffix("/"), size: size, modifiedAt: date)) }
        }
        else if elementName == "NextContinuationToken", !text.isEmpty { nextContinuationToken = text }
    }
}

private final class ErrorParser: NSObject, XMLParserDelegate {
    private var text = "", message = ""
    func parse(_ data: Data) -> String { let parser = XMLParser(data: data); parser.delegate = self; parser.parse(); return message }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) { text = "" }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if elementName == "Message" { message = text } }
}
