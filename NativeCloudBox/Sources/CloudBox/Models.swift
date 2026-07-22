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

enum UploadState: Equatable {
    case queued, uploading, completed, failed(String)
}

struct UploadEntry: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let remoteKey: String
    let relativePath: String
    let size: Int64
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
