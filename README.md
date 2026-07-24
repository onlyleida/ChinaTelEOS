# 翼存 CloudBox（原生 macOS）

天翼云对象存储文件管理器。应用使用 SwiftUI 与 URLSession 构建，凭证保存在本地配置文件中。

## 功能

- 按对象前缀浏览和管理文件夹
- 列表 / 图标两种显示模式；图标模式支持拖动滑块或捏合调整大小
- 新建文件夹、进入子目录和面包屑导航
- 将一个或多个文件/文件夹拖到当前目录上传
- 通过系统选择器上传单个文件、多个文件或完整文件夹
- 递归遍历文件夹中的所有子文件并保持目录结构
- 上传前询问是否开启公共读
- 显示单文件进度和总体上传进度
- 为文件或文件夹下全部对象设置读写权限（私有 / 公共读 / 公共读写）
- 删除文件；删除文件夹时同时删除其全部对象
- Access Key 和 Secret Key 保存在项目目录 `cloudbox.local.json`（已加入 `.gitignore`，不进入 Git）

## 系统要求

- macOS 14 或更高版本
- Xcode 16 或更高版本（仅从源码构建时需要）
- 天翼云对象存储的 S3 兼容 Endpoint、区域、存储桶和访问密钥

## 运行

```bash
./scripts/build_native_app.sh
open "build/翼存 CloudBox.app"
```

开发时也可以直接运行：

```bash
swift run CloudBox
```

运行测试：

```bash
swift test
```

## 凭证与个人配置

| 内容 | 存放位置 | 是否进 Git |
|------|----------|------------|
| Access Key / Secret Key / Endpoint 等 | 项目根目录 `cloudbox.local.json` | 否（已 ignore） |
| VS Code / Cursor 个人设置 | `.vscode/settings.json`（本地） | 否（已 ignore） |
| 共享构建与 Push 任务 | `.vscode/tasks.json` | 是 |

首次连接成功后会写入 `cloudbox.local.json`，下次启动自动加载。

## 项目结构

```text
NativeCloudBox/Sources/CloudBox/
  CloudBoxApp.swift       App 入口
  ContentView.swift       原生文件管理界面及拖放
  CloudViewModel.swift    目录、删除和递归上传流程
  CloudClient.swift       天翼云 S3 兼容 API
  AWSSigner.swift         AWS Signature V4 请求签名
  ConfigStore.swift       本地 `cloudbox.local.json` 凭证存储
  Models.swift            配置与上传任务模型
```
