import Foundation
import Darwin

final class DeviceManager {
    static let shared = DeviceManager()
    
    private let storageKey = "MacStatusDeviceUUID"
    let deviceUUID: UUID
    
    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: storageKey), let uuid = UUID(uuidString: stored) {
            deviceUUID = uuid
        } else {
            let uuid = UUID()
            deviceUUID = uuid
            defaults.set(uuid.uuidString, forKey: storageKey)
        }
    }
    
    var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
    
    var model: String {
        Self.sysctlString("hw.model") ?? "Mac"
    }
    
    var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
    
    private static func sysctlString(_ key: String) -> String? {
        var size: size_t = 0
        if sysctlbyname(key, nil, &size, nil, 0) != 0 || size == 0 { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        if sysctlbyname(key, &buffer, &size, nil, 0) != 0 { return nil }
        return String(cString: buffer)
    }
}

