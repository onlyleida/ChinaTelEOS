import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = CloudViewModel()
    @State private var isDropTarget = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $model.isShowingConnection) { ConnectionView(model: model) }
        .alert("发生错误", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { if !model.isShowingConnection { await model.connect() } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button(action: model.chooseUpload) { Label("上传文件或文件夹", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large).padding()
            List {
                Label("全部文件", systemImage: "folder.fill").foregroundStyle(.blue)
                Section("位置") {
                    Button { model.navigate(to: nil) } label: { Label(model.configuration.bucket.isEmpty ? "存储桶" : model.configuration.bucket, systemImage: "externaldrive.fill") }
                }
            }
            HStack(spacing: 8) {
                Circle().fill(model.isConnected ? .green : .gray).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isConnected ? "连接正常" : "未连接").font(.caption).fontWeight(.medium)
                    Text(model.configuration.region).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.isShowingConnection = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain)
            }.padding()
        }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isLoading && model.items.isEmpty { ProgressView("正在读取目录…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if model.visibleItems.isEmpty { emptyState }
            else { fileTable }
            if !model.uploads.isEmpty { uploadPanel }
        }
        .background(isDropTarget ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .overlay { if isDropTarget { dropOverlay } }
        .dropDestination(for: URL.self) { urls, _ in model.enqueue(urls); return true } isTargeted: { isDropTarget = $0 }
        .toolbar {
            ToolbarItemGroup {
                Button(action: model.refresh) { Label("刷新", systemImage: "arrow.clockwise") }
                Button(action: model.createFolder) { Label("新建文件夹", systemImage: "folder.badge.plus") }
                Button(action: model.chooseUpload) { Label("上传", systemImage: "square.and.arrow.up") }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索当前文件夹")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("天翼云对象存储").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { model.navigate(to: nil) } label: { Image(systemName: "house.fill") }.buttonStyle(.plain)
                ForEach(Array(model.path.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Button(component.name) { model.navigate(to: index) }.buttonStyle(.plain).fontWeight(index == model.path.count - 1 ? .semibold : .regular)
                }
                Spacer(); Text("\(model.visibleItems.count) 项").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var fileTable: some View {
        Table(model.visibleItems, selection: $model.selected) {
            TableColumn("名称") { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isFolder ? "folder.fill" : icon(for: item.name)).foregroundStyle(item.isFolder ? .blue : .secondary).font(.title3)
                    Text(item.name).lineLimit(1)
                }.contentShape(Rectangle()).onTapGesture(count: 2) { model.open(item) }
                 .contextMenu {
                    if item.isFolder { Button("打开") { model.open(item) } }
                    Divider(); Button("删除", role: .destructive) { model.confirmDelete(item) }
                }
            }.width(min: 260, ideal: 430)
            TableColumn("大小") { item in Text(item.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).foregroundStyle(.secondary) }.width(100)
            TableColumn("修改时间") { item in Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—").foregroundStyle(.secondary) }.width(150)
        }
        .onDeleteCommand { if let id = model.selected, let item = model.items.first(where: { $0.id == id }) { model.confirmDelete(item) } }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.searchText.isEmpty ? "此文件夹为空" : "未找到文件", systemImage: "folder")
        } description: { Text(model.searchText.isEmpty ? "把文件或文件夹拖到这里即可上传" : "请尝试其他关键词") }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16).fill(.regularMaterial).strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(18)
            .overlay { VStack(spacing: 12) { Image(systemName: "square.and.arrow.down.fill").font(.system(size: 42)).foregroundStyle(.blue); Text("上传到当前文件夹").font(.title2).fontWeight(.semibold); Text("支持多个文件和完整文件夹").foregroundStyle(.secondary) } }
    }

    private var uploadPanel: some View {
        VStack(spacing: 8) {
            HStack { Label("上传任务", systemImage: "arrow.up.circle.fill").fontWeight(.semibold); Spacer(); Text("\(model.uploads.filter { $0.state == .completed }.count)/\(model.uploads.count)").foregroundStyle(.secondary); Button("清除已完成") { model.uploads.removeAll { $0.state == .completed } }.disabled(!model.uploads.contains { $0.state == .completed }) }
            ProgressView(value: model.overallProgress)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.uploads) { entry in
                        HStack {
                            Image(systemName: entry.state == .completed ? "checkmark.circle.fill" : "doc.fill").foregroundStyle(entry.state == .completed ? .green : .blue)
                            VStack(alignment: .leading, spacing: 3) { Text(entry.relativePath).lineLimit(1); ProgressView(value: entry.fraction).controlSize(.small) }
                            Text(status(entry)).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }.frame(maxHeight: 130)
        }.padding(14).background(.bar).overlay(alignment: .top) { Divider() }
    }

    private func status(_ entry: UploadEntry) -> String {
        switch entry.state { case .queued: "等待中"; case .uploading: "\(Int(entry.fraction * 100))%"; case .completed: "完成"; case .failed: "失败" }
    }
    private func icon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic"].contains(ext) { return "photo.fill" }
        if ["mp4", "mov", "m4v"].contains(ext) { return "film.fill" }
        if ["zip", "gz", "rar", "7z"].contains(ext) { return "archivebox.fill" }
        return "doc.fill"
    }
}

private struct ConnectionView: View {
    @ObservedObject var model: CloudViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "externaldrive.connected.to.line.below.fill").font(.title).foregroundStyle(.blue); VStack(alignment: .leading) { Text("连接天翼云对象存储").font(.title2).fontWeight(.bold); Text("使用 S3 兼容 Endpoint，凭证保存在 macOS 钥匙串中。") .font(.caption).foregroundStyle(.secondary) } }
            Form {
                TextField("Endpoint", text: $model.configuration.endpoint)
                TextField("区域", text: $model.configuration.region)
                TextField("存储桶", text: $model.configuration.bucket)
                TextField("Access Key", text: $model.configuration.accessKey)
                SecureField("Secret Key", text: $model.configuration.secretKey)
            }.formStyle(.grouped)
            HStack { Spacer(); if model.isConnected { Button("取消") { dismiss() } }; Button("连接") { Task { await model.connect() } }.buttonStyle(.borderedProminent).disabled(!model.configuration.isValid || model.isLoading) }
        }.padding(26).frame(width: 520)
    }
}
