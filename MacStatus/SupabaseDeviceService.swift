import Foundation

struct MacStatusDevice: Codable, Identifiable {
    let id: String
    let device_uuid: String
    let device_name: String?
    let model: String?
    let os_version: String?
    let app_version: String?
    let last_seen_at: String?
    let created_at: String?
}

private struct DeviceUpsertPayload: Codable {
    let user_id: String
    let device_uuid: String
    let device_name: String
    let model: String
    let os_version: String
    let app_version: String
    let last_seen_at: String
}

class SupabaseDeviceService {
    private let config: SupabaseConfig
    
    init(config: SupabaseConfig) {
        self.config = config
    }
    
    func upsertCurrentDevice(session: SupabaseSession) async throws -> String {
        let rawUserId = session.user?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = (rawUserId?.isEmpty == false) ? rawUserId : JWT.claim(session.accessToken, key: "sub")
        guard let userId, !userId.isEmpty else {
            throw AuthError.network("设备注册缺少 user_id（无法从 session.user.id 或 access token 的 sub 解析）。")
        }
        
        var components = URLComponents(url: config.url.appendingPathComponent("rest/v1/mac_status_devices"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id,device_uuid"),
            URLQueryItem(name: "select", value: "id")
        ]
        guard let url = components?.url else { throw AuthError.network("无法拼接设备注册地址。") }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let device = DeviceManager.shared
        let payload = DeviceUpsertPayload(
            user_id: userId,
            device_uuid: device.deviceUUID.uuidString,
            device_name: device.deviceName,
            model: device.model,
            os_version: device.osVersion,
            app_version: device.appVersion,
            last_seen_at: isoFormatter.string(from: Date())
        )
        
        request.httpBody = try JSONEncoder().encode([payload])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network("设备注册失败：无有效响应。") }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("设备注册失败 (\(http.statusCode))：\(msg)")
        }
        
        struct DeviceUpsertResult: Decodable { let id: String }
        let rows = try JSONDecoder().decode([DeviceUpsertResult].self, from: data)
        guard let id = rows.first?.id, !id.isEmpty else {
            throw AuthError.network("设备注册成功但未返回 device_id。")
        }
        return id
    }
    
    func fetchDevices(session: SupabaseSession) async throws -> [MacStatusDevice] {
        var components = URLComponents(url: config.url.appendingPathComponent("rest/v1/mac_status_devices"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,device_uuid,device_name,model,os_version,app_version,last_seen_at,created_at"),
            URLQueryItem(name: "order", value: "last_seen_at.desc")
        ]
        guard let url = components?.url else { throw AuthError.network("无法拼接设备列表地址。") }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network("获取设备列表失败：无有效响应。") }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("获取设备列表失败 (\(http.statusCode))：\(msg)")
        }
        
        return try JSONDecoder().decode([MacStatusDevice].self, from: data)
    }
    
    func updateDeviceName(id: String, newName: String, session: SupabaseSession) async throws {
        let url = config.url.appendingPathComponent("rest/v1/mac_status_devices")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        guard let finalUrl = components?.url else { throw AuthError.network("无法拼接重命名地址。") }
        
        var request = URLRequest(url: finalUrl)
        request.httpMethod = "PATCH"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["device_name": newName]
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network("更新设备名称失败：无有效响应。") }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("更新设备名称失败 (\(http.statusCode))：\(msg)")
        }
    }
    
    func deleteDevice(id: String, session: SupabaseSession) async throws {
        let url = config.url.appendingPathComponent("rest/v1/mac_status_devices")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        guard let finalUrl = components?.url else { throw AuthError.network("无法拼接删除地址。") }
        
        var request = URLRequest(url: finalUrl)
        request.httpMethod = "DELETE"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network("删除设备失败：无有效响应。") }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("删除设备失败 (\(http.statusCode))：\(msg)")
        }
    }
}
