import SwiftUI

@main
struct CloudBoxApp: App {
    var body: some Scene {
        WindowGroup("翼存 CloudBox") { ContentView() }
            .defaultSize(width: 1180, height: 760)
        Settings { Text("连接设置可在主窗口左下角打开。") .padding(30) }
    }
}
