import Foundation
import CryptoKit

enum AWSSigner {
    static func signedRequest(url: URL, method: String, bodyHash: String, configuration: CloudConfiguration, date: Date = Date()) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: date)

        let host = url.host ?? ""
        let path = url.path.isEmpty ? "/" : encodedPath(url.path)
        let query = canonicalQuery(url)
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(bodyHash)\nx-amz-date:\(timestamp)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = "\(method)\n\(path)\n\(query)\n\(canonicalHeaders)\n\(signedHeaders)\n\(bodyHash)"
        let scope = "\(day)/\(configuration.region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(sha256(canonicalRequest.data(using: .utf8)!))"
        let dateKey = hmac(Data(("AWS4" + configuration.secretKey).utf8), day)
        let regionKey = hmac(dateKey, configuration.region)
        let serviceKey = hmac(regionKey, "s3")
        let signingKey = hmac(serviceKey, "aws4_request")
        let signature = hmac(signingKey, stringToSign).map { String(format: "%02x", $0) }.joined()

        request.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(bodyHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("AWS4-HMAC-SHA256 Credential=\(configuration.accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1024 * 1024)
            guard let data, !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(_ key: Data, _ value: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
    }

    private static func encodedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: ":?#[]@!$&'()*+,;="))) ?? String($0) }
            .joined(separator: "/")
    }

    private static func canonicalQuery(_ url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items: [URLQueryItem] = components?.queryItems ?? []
        var pairs: [(String, String)] = items.map { item in
            (percent(item.name), percent(item.value ?? ""))
        }
        pairs.sort { left, right in
            if left.0 == right.0 { return left.1 < right.1 }
            return left.0 < right.0
        }
        return pairs.map { pair in pair.0 + "=" + pair.1 }.joined(separator: "&")
    }

    private static func percent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? value
    }
}
