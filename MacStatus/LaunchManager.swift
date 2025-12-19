import Foundation
import ServiceManagement
import OSLog

@MainActor
final class LaunchManager: ObservableObject {
    static let shared = LaunchManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacStatus", category: "LaunchManager")
    
    @Published private(set) var isLaunchAtLoginEnabled: Bool = false
    
    private init() {
        checkStatus()
    }
    
    func checkStatus() {
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                logger.info("Successfully unregistered login item.")
            } else {
                try SMAppService.mainApp.register()
                logger.info("Successfully registered login item.")
            }
        } catch {
            logger.error("Failed to update login item status: \(error.localizedDescription)")
        }
        checkStatus()
    }
}

