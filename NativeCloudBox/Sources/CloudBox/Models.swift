import Foundation

struct CloudConfiguration: Codable, Equatable {
    var endpoint = "https://oos-cn.ctyunapi.cn"
    var region = "cn-shanghai"
    var bucket = ""
    var accessKey = ""
    var secretKey = ""

    var isValid: Bool {
        URL(string: endpoint) != nil && !bucket.isEmpty && !accessKey.isEmpty && !secretKey.isEmpty
    }
}

struct CloudItem: Identifiable, Hashable {
    let key: String
    let name: String
    let isFolder: Bool
    let size: Int64
    let modifiedAt: Date?
    var id: String { key }
}

/// S3 canned ACL used by 天翼云对象存储.
enum ObjectAcl: String, CaseIterable, Identifiable {
    case `private`
    case publicRead
    case publicReadWrite

    var id: String { rawValue }

    var headerValue: String {
        switch self {
        case .private: "private"
        case .publicRead: "public-read"
        case .publicReadWrite: "public-read-write"
        }
    }

    var title: String {
        switch self {
        case .private: "私有"
        case .publicRead: "公共读"
        case .publicReadWrite: "公共读写"
        }
    }

    var detail: String {
        switch self {
        case .private: "仅持有密钥的用户可访问"
        case .publicRead: "知道链接的人可下载，但不能写入"
        case .publicReadWrite: "知道链接的人可读可写（请谨慎使用）"
        }
    }
}

enum UploadState: Equatable {
    case queued, uploading, completed, failed(String)
}

struct UploadEntry: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let remoteKey: String
    let relativePath: String
    let size: Int64
    let acl: ObjectAcl
    var sent: Int64 = 0
    var state: UploadState = .queued

    var fraction: Double { size == 0 ? (state == .completed ? 1 : 0) : min(1, Double(sent) / Double(size)) }
}

enum CloudError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "连接信息不完整"
        case .invalidResponse: "服务器返回了无法识别的数据"
        case let .server(status, message): "天翼云请求失败（\(status)）：\(message)"
        }
    }
}
