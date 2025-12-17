import Foundation

fileprivate enum JSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        }
    }
}

fileprivate struct MetricsPayload: Codable {
    let user_id: String?
    let device_id: String?
    let cpu_usage: Double
    let memory_usage: Double
    let used_memory_gb: Double
    let total_memory_gb: Double
    let disk_read_mb_s: Double
    let disk_write_mb_s: Double
    let network_download_mb_s: Double?
    let network_upload_mb_s: Double?
    let payload: [String: JSONValue]?
    let created_at: String
}

class SupabaseMetricsService {
    private let config: SupabaseConfig
    
    init(config: SupabaseConfig) {
        self.config = config
    }
    
    func upload(snapshot: MetricsSnapshot, session: SupabaseSession, deviceId: String) async throws {
        let endpoint = config.url.appendingPathComponent("rest/v1/mac_status_metrics")
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let rawUserId = session.user?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = (rawUserId?.isEmpty == false) ? rawUserId : JWT.claim(session.accessToken, key: "sub")
        guard let userId, !userId.isEmpty else {
            throw AuthError.network("上传缺少 user_id（无法从 session.user.id 或 access token 的 sub 解析）。")
        }
        
        let createdAt = isoFormatter.string(from: snapshot.timestamp)
        let device = DeviceManager.shared
        let payload: [String: JSONValue] = [
            "cpu_usage": .double(snapshot.cpuUsage),
            "memory_usage": .double(snapshot.memoryUsage),
            "used_memory_gb": .double(snapshot.usedMemoryGB),
            "total_memory_gb": .double(snapshot.totalMemoryGB),
            "device_id": .string(deviceId),
            "disk_usage": .double(snapshot.diskUsage),
            "disk_used_gb": .double(snapshot.diskUsedGB),
            "disk_total_gb": .double(snapshot.diskTotalGB),
            "disk_read_mb_s": .double(snapshot.diskReadSpeedMBps),
            "disk_write_mb_s": .double(snapshot.diskWriteSpeedMBps),
            "network_download_mb_s": .double(snapshot.networkDownloadSpeedMBps),
            "network_upload_mb_s": .double(snapshot.networkUploadSpeedMBps),
            "device_uuid": .string(device.deviceUUID.uuidString),
            "device_name": .string(device.deviceName),
            "model": .string(device.model),
            "os_version": .string(device.osVersion),
            "app_version": .string(device.appVersion)
        ]
        let v2 = MetricsPayload(
            user_id: userId,
            device_id: deviceId,
            cpu_usage: snapshot.cpuUsage,
            memory_usage: snapshot.memoryUsage,
            used_memory_gb: snapshot.usedMemoryGB,
            total_memory_gb: snapshot.totalMemoryGB,
            disk_read_mb_s: snapshot.diskReadSpeedMBps,
            disk_write_mb_s: snapshot.diskWriteSpeedMBps,
            network_download_mb_s: snapshot.networkDownloadSpeedMBps,
            network_upload_mb_s: snapshot.networkUploadSpeedMBps,
            payload: payload,
            created_at: createdAt
        )
        
        do {
            try await performUpload(payload: v2, endpoint: endpoint, session: session)
        } catch AuthError.network(let message) {
            if shouldFallbackToLegacySchema(message) {
                let v1 = MetricsPayload(
                    user_id: userId,
                    device_id: nil,
                    cpu_usage: snapshot.cpuUsage,
                    memory_usage: snapshot.memoryUsage,
                    used_memory_gb: snapshot.usedMemoryGB,
                    total_memory_gb: snapshot.totalMemoryGB,
                    disk_read_mb_s: snapshot.diskReadSpeedMBps,
                    disk_write_mb_s: snapshot.diskWriteSpeedMBps,
                    network_download_mb_s: nil,
                    network_upload_mb_s: nil,
                    payload: nil,
                    created_at: createdAt
                )
                try await performUpload(payload: v1, endpoint: endpoint, session: session)
            } else {
                throw AuthError.network(message)
            }
        }
    }
    
    private func performUpload(payload: MetricsPayload, endpoint: URL, session: SupabaseSession) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode([payload])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("上传失败：无有效响应。")
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("上传失败 (\(http.statusCode))：\(msg)")
        }
    }
    
    private func shouldFallbackToLegacySchema(_ message: String) -> Bool {
        let lower = message.lowercased()
        if !(lower.contains("400")) { return false }
        let indicatesUnknownColumn = lower.contains("column") || lower.contains("unknown") || lower.contains("not found") || lower.contains("does not exist")
        let mentionsNewKey =
            lower.contains("network_download_mb_s") ||
            lower.contains("network_upload_mb_s") ||
            lower.contains("device_id") ||
            lower.contains("network_download") ||
            lower.contains("network_upload") ||
            lower.contains("payload")
        return indicatesUnknownColumn && mentionsNewKey
    }
}
