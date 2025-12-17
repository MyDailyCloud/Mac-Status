import SwiftUI
import AppKit

@MainActor
final class MacStatusAppState {
    static let shared = MacStatusAppState()
    let monitor: SystemMonitor
    let authManager: AuthManager
    
    private init() {
        monitor = SystemMonitor(autoStart: false)
        authManager = AuthManager()
    }
}

@main
struct MacStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Mac Status") {
            RootView(monitor: MacStatusAppState.shared.monitor)
                .environmentObject(MacStatusAppState.shared.authManager)
        }
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var systemMonitor: SystemMonitor!
    var authManager: AuthManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "系统状态")
            button.target = self
            button.action = #selector(togglePopover)
        }
        
        // 共享状态（窗口 Dashboard / 菜单栏弹窗使用同一份登录与监控状态）
        systemMonitor = MacStatusAppState.shared.monitor
        authManager = MacStatusAppState.shared.authManager
        
        // 创建弹出窗口
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: RootView(monitor: systemMonitor)
                .environmentObject(authManager)
        )
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
