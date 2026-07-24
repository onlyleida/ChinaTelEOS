import AppKit
import SwiftUI

@MainActor
final class CloudViewModel: ObservableObject {
    @Published var configuration = ConfigStore.load() ?? CloudConfiguration()
    @Published var isShowingConnection = ConfigStore.load() == nil
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var items: [CloudItem] = []
    @Published var prefix = ""
    @Published var path: [(name: String, prefix: String)] = []
    @Published var selected: CloudItem.ID?
    @Published var uploads: [UploadEntry] = []
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var client: CloudClient?

    var visibleItems: [CloudItem] {
        searchText.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    var overallProgress: Double {
        let total = uploads.reduce(Int64(0)) { $0 + max($1.size, 1) }
        guard total > 0 else { return 0 }
        let sent = uploads.reduce(Int64(0)) { $0 + ($1.state == .completed ? max($1.size, 1) : $1.sent) }
        return Double(sent) / Double(total)
    }

    func connect() async {
        guard configuration.isValid else { errorMessage = CloudError.invalidConfiguration.localizedDescription; return }
        do {
            client = CloudClient(configuration: configuration)
            try await refreshThrowing()
            try ConfigStore.save(configuration)
            isConnected = true
            isShowingConnection = false
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() { Task { do { try await refreshThrowing() } catch { errorMessage = error.localizedDescription } } }

    func open(_ item: CloudItem) {
        guard item.isFolder else { return }
        path.append((item.name, item.key)); prefix = item.key; selected = nil; refresh()
    }

    func navigate(to index: Int?) {
        if let index { prefix = path[index].prefix; path = Array(path.prefix(index + 1)) }
        else { prefix = ""; path = [] }
        selected = nil; refresh()
    }

    func createFolder() {
        let alert = NSAlert(); alert.messageText = "新建文件夹"; alert.informativeText = "输入文件夹名称"
        let field = NSTextField(string: "新建文件夹"); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { errorMessage = "文件夹名称不能为空或包含 /"; return }
        Task { do { try await client?.createFolder(key: prefix + name + "/"); try await refreshThrowing() } catch { errorMessage = error.localizedDescription } }
    }

    func confirmDelete(_ item: CloudItem) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "删除“\(item.name)”？"
        alert.informativeText = item.isFolder ? "文件夹及其中所有内容都会被永久删除。" : "该文件会被永久删除。"
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { do { try await client?.delete(item: item); selected = nil; try await refreshThrowing() } catch { errorMessage = error.localizedDescription } }
    }

    func chooseUpload() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "上传"; if panel.runModal() == .OK { enqueue(panel.urls) }
    }

    func enqueue(_ urls: [URL]) {
        guard let acl = askPublicReadForUpload() else { return }
        do {
            let entries = try urls.flatMap { try Self.expand($0, remotePrefix: prefix, acl: acl) }
            uploads.append(contentsOf: entries)
            Task { await runQueuedUploads() }
        } catch { errorMessage = error.localizedDescription }
    }

    func confirmSetPermissions(_ item: CloudItem) {
        guard let acl = askObjectAcl(
            title: "设置读写权限",
            message: item.isFolder
                ? "为文件夹「\(item.name)」下的所有文件设置访问权限。"
                : "为文件「\(item.name)」设置访问权限。"
        ) else { return }
        Task {
            do {
                let count = try await client?.setAcl(item: item, acl: acl) ?? 0
                let alert = NSAlert()
                alert.messageText = "权限已更新"
                alert.informativeText = item.isFolder
                    ? "已将 \(count) 个对象设置为「\(acl.title)」。"
                    : "「\(item.name)」已设置为「\(acl.title)」。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func askPublicReadForUpload() -> ObjectAcl? {
        let alert = NSAlert()
        alert.messageText = "上传权限"
        alert.informativeText = "是否支持公共读？开启后，知道对象链接的人无需密钥即可下载。"
        alert.addButton(withTitle: "公共读")
        alert.addButton(withTitle: "仅私有")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .publicRead
        case .alertSecondButtonReturn: return .private
        default: return nil
        }
    }

    private func askObjectAcl(title: String, message: String) -> ObjectAcl? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for acl in ObjectAcl.allCases {
            popup.addItem(withTitle: "\(acl.title) — \(acl.detail)")
            popup.lastItem?.representedObject = acl.rawValue
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let raw = popup.selectedItem?.representedObject as? String ?? ObjectAcl.private.rawValue
        return ObjectAcl(rawValue: raw) ?? .private
    }

    private func runQueuedUploads() async {
        guard let client else { errorMessage = "请先连接天翼云"; return }
        while let index = uploads.firstIndex(where: { $0.state == .queued }) {
            uploads[index].state = .uploading
            let entry = uploads[index]
            do {
                try await client.uploadFile(file: entry.sourceURL, key: entry.remoteKey, acl: entry.acl) { [weak self] sent, total in
                    Task { @MainActor in
                        guard let self, let current = self.uploads.firstIndex(where: { $0.id == entry.id }) else { return }
                        self.uploads[current].sent = total > 0 ? min(sent, total) : sent
                    }
                }
                if let current = uploads.firstIndex(where: { $0.id == entry.id }) { uploads[current].sent = entry.size; uploads[current].state = .completed }
            } catch {
                if let current = uploads.firstIndex(where: { $0.id == entry.id }) { uploads[current].state = .failed(error.localizedDescription) }
            }
        }
        refresh()
    }

    private func refreshThrowing() async throws {
        if client == nil { client = CloudClient(configuration: configuration) }
        isLoading = true; defer { isLoading = false }
        items = try await client!.list(prefix: prefix)
    }

    nonisolated static func expand(_ url: URL, remotePrefix: String, acl: ObjectAcl = .private) throws -> [UploadEntry] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory == true else {
            return [UploadEntry(sourceURL: url, remoteKey: remotePrefix + url.lastPathComponent, relativePath: url.lastPathComponent, size: Int64(values.fileSize ?? 0), acl: acl)]
        }
        let root = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var result: [UploadEntry] = []
        while let child = enumerator?.nextObject() as? URL {
            let childValues = try child.resourceValues(forKeys: keys)
            guard childValues.isRegularFile == true else { continue }
            let resolvedChild = child.resolvingSymlinksInPath()
            let relative = resolvedChild.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            result.append(UploadEntry(sourceURL: child, remoteKey: remotePrefix + relative, relativePath: relative, size: Int64(childValues.fileSize ?? 0), acl: acl))
        }
        return result
    }
}
