import SwiftUI
import UniformTypeIdentifiers

private enum BrowseDisplayMode: String, CaseIterable, Identifiable {
    case list
    case icons

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .icons: "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .list: "列表"
        case .icons: "图标"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = CloudViewModel()
    @State private var isDropTarget = false
    @AppStorage("browseDisplayMode") private var displayModeRaw = BrowseDisplayMode.list.rawValue
    @AppStorage("browseIconSize") private var iconSize = 72.0
    @State private var iconSizeAtGestureStart: Double?

    private var displayMode: BrowseDisplayMode {
        BrowseDisplayMode(rawValue: displayModeRaw) ?? .list
    }

    private var clampedIconSize: Double {
        min(160, max(48, iconSize))
    }

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
            else {
                switch displayMode {
                case .list: fileTable
                case .icons: fileIcons
                }
            }
            if displayMode == .icons { iconSizeBar }
            if !model.uploads.isEmpty { uploadPanel }
        }
        .background(isDropTarget ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .overlay { if isDropTarget { dropOverlay } }
        .dropDestination(for: URL.self) { urls, _ in model.enqueue(urls); return true } isTargeted: { isDropTarget = $0 }
        .toolbar {
            ToolbarItemGroup {
                Picker("显示模式", selection: $displayModeRaw) {
                    ForEach(BrowseDisplayMode.allCases) { mode in
                        Image(systemName: mode.systemImage).tag(mode.rawValue).help(mode.label)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 84)

                Button(action: model.refresh) { Label("刷新", systemImage: "arrow.clockwise") }
                Button(action: model.createFolder) { Label("新建文件夹", systemImage: "folder.badge.plus") }
                Button(action: model.chooseUpload) { Label("上传", systemImage: "square.and.arrow.up") }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索当前文件夹")
        .onDeleteCommand { deleteSelected() }
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
                    Image(systemName: item.isFolder ? "folder.fill" : iconName(for: item.name)).foregroundStyle(item.isFolder ? .blue : .secondary).font(.title3)
                    Text(item.name).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(item) }
                .contextMenu { itemContextMenu(item) }
            }.width(min: 260, ideal: 430)
            TableColumn("大小") { item in Text(item.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).foregroundStyle(.secondary) }.width(100)
            TableColumn("修改时间") { item in Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—").foregroundStyle(.secondary) }.width(150)
        }
    }

    private var fileIcons: some View {
        let size = clampedIconSize
        let cellWidth = size + 36
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 12), spacing: 8)],
                spacing: 12
            ) {
                ForEach(model.visibleItems) { item in
                    iconCell(item, iconSize: size)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    if iconSizeAtGestureStart == nil { iconSizeAtGestureStart = clampedIconSize }
                    if let start = iconSizeAtGestureStart {
                        iconSize = min(160, max(48, start * scale))
                    }
                }
                .onEnded { _ in iconSizeAtGestureStart = nil }
        )
    }

    private func iconCell(_ item: CloudItem, iconSize: Double) -> some View {
        let selected = model.selected == item.id
        return VStack(spacing: 8) {
            Image(systemName: item.isFolder ? "folder.fill" : iconName(for: item.name))
                .font(.system(size: iconSize * 0.72))
                .foregroundStyle(item.isFolder ? .blue : .secondary)
                .frame(width: iconSize, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                )

            Text(item.name)
                .font(.system(size: max(11, min(13, iconSize * 0.16))))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: iconSize + 28)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .frame(width: iconSize + 36)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(item) }
        .onTapGesture { model.selected = item.id }
        .contextMenu { itemContextMenu(item) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconSizeBar: some View {
        HStack(spacing: 10) {
            Text("\(model.visibleItems.count) 项").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "minus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { clampedIconSize },
                set: { iconSize = $0 }
            ), in: 48...160)
            .frame(width: 140)
            .help("拖动调整图标大小")
            Image(systemName: "plus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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

    @ViewBuilder
    private func itemContextMenu(_ item: CloudItem) -> some View {
        if item.isFolder { Button("打开") { model.open(item) } }
        Button("设置读写权限…") { model.confirmSetPermissions(item) }
        Divider()
        Button("删除", role: .destructive) { model.confirmDelete(item) }
    }

    private func deleteSelected() {
        guard let id = model.selected, let item = model.items.first(where: { $0.id == id }) else { return }
        model.confirmDelete(item)
    }

    private func status(_ entry: UploadEntry) -> String {
        switch entry.state { case .queued: "等待中"; case .uploading: "\(Int(entry.fraction * 100))%"; case .completed: "完成"; case .failed: "失败" }
    }

    private func iconName(for name: String) -> String {
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
            HStack { Image(systemName: "externaldrive.connected.to.line.below.fill").font(.title).foregroundStyle(.blue); VStack(alignment: .leading) { Text("连接天翼云对象存储").font(.title2).fontWeight(.bold); Text("使用 S3 兼容 Endpoint，连接成功后写入当前目录 \(ConfigStore.fileName)。") .font(.caption).foregroundStyle(.secondary) } }
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
