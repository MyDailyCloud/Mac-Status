import SwiftUI
import AppKit
import Combine

@MainActor
final class MacStatusAppState {
    static let shared = MacStatusAppState()
    let monitor: SystemMonitor
    let authManager: AuthManager
    let uploader: MetricsUploader
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        monitor = SystemMonitor(autoStart: false)
        authManager = AuthManager()
        uploader = MetricsUploader()
        
        setupSync()
    }
    
    private func setupSync() {
        // 监听登录状态变化，自动开启/停止监控
        authManager.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if case .authenticated = state {
                    self.monitor.startMonitoring()
                } else {
                    self.monitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)
        
        // 统一处理监控指标回调
        monitor.onMetricsUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.uploader.handle(snapshot: snapshot, authManager: self.authManager)
        }
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
            SettingsView(monitor: MacStatusAppState.shared.monitor)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var systemMonitor: SystemMonitor!
    var authManager: AuthManager!
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "系统状态")
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeft
        }
        
        // 共享状态（窗口 Dashboard / 菜单栏弹窗使用同一份登录与监控状态）
        systemMonitor = MacStatusAppState.shared.monitor
        authManager = MacStatusAppState.shared.authManager
        
        setupMenuBarObservation()
        
        // 创建弹出窗口
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: RootView(monitor: systemMonitor)
                .environmentObject(authManager)
        )
    }
    
    private func setupMenuBarObservation() {
        systemMonitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarTitle()
            }
            .store(in: &cancellables)
    }
    
    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }
        
        let displayType = UserDefaults.standard.string(forKey: "MenuBarDisplayType") ?? "none"
        
        switch displayType {
        case "cpu":
            button.title = String(format: " %.0f%%", systemMonitor.cpuUsage)
        case "mem":
            button.title = String(format: " %.0f%%", systemMonitor.memoryUsage)
        case "net":
            button.title = " \(systemMonitor.networkDownloadSpeed)M"
        default:
            button.title = ""
        }
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
