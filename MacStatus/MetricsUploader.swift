import Foundation

@MainActor
class MetricsUploader: ObservableObject {
    private let service: SupabaseMetricsService?
    private var lastUploadDate: Date?
    private let minInterval: TimeInterval = 5
    
    @Published var lastUploadAttemptAt: Date?
    @Published var lastUploadSucceededAt: Date?
    @Published var lastUploadErrorMessage: String?
    
    init() {
        if let config = SupabaseConfig.load() {
            service = SupabaseMetricsService(config: config)
        } else {
            service = nil
        }
    }
    
    func handle(snapshot: MetricsSnapshot, authManager: AuthManager) {
        let now = Date()
        if let last = lastUploadDate, now.timeIntervalSince(last) < minInterval { return }
        lastUploadDate = now
        lastUploadAttemptAt = now
        
        guard let service = service else {
            lastUploadErrorMessage = AuthError.configurationMissing.localizedDescription
            return
        }
        
        Task {
            guard let session = await authManager.ensureValidSession() else {
                await MainActor.run {
                    self.lastUploadErrorMessage = "未获取到有效登录 session（可能 access token 已过期且没有 refresh_token）。"
                }
                return
            }
            
            do {
                try await service.upload(snapshot: snapshot, session: session)
                await MainActor.run {
                    self.lastUploadSucceededAt = Date()
                    self.lastUploadErrorMessage = nil
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.lastUploadErrorMessage = message
                }
            }
        }
    }
}
