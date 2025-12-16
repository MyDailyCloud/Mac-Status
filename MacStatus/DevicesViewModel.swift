import Foundation

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published var devices: [MacStatusDevice] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let service: SupabaseDeviceService?
    
    init() {
        if let config = SupabaseConfig.load() {
            service = SupabaseDeviceService(config: config)
        } else {
            service = nil
        }
    }
    
    func refresh(authManager: AuthManager) async {
        guard let service = service else {
            errorMessage = AuthError.configurationMissing.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        guard let session = await authManager.ensureValidSession() else {
            errorMessage = "未获取到有效登录 session（可能 access token 已过期且没有 refresh_token）。"
            return
        }
        
        do {
            try await service.upsertCurrentDevice(session: session)
            devices = try await service.fetchDevices(session: session)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
