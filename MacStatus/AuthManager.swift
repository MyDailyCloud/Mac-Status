import Foundation
import Combine
import AuthenticationServices
import AppKit

private enum DotEnv {
    static func load() -> [String: String] {
        for url in candidateURLs() {
            if let dict = loadFile(url: url), !dict.isEmpty {
                return dict
            }
        }
        return [:]
    }
    
    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(".env"))
        }
        
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("MacStatus/.env"))
            if let bundleId = Bundle.main.bundleIdentifier {
                urls.append(appSupport.appendingPathComponent(bundleId).appendingPathComponent(".env"))
            }
        }
        
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        urls.append(cwd.appendingPathComponent(".env"))
        
        return urls
    }
    
    private static func loadFile(url: URL) -> [String: String]? {
        guard
            let data = try? Data(contentsOf: url),
            let contents = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        
        return parse(contents: contents)
    }
    
    private static func parse(contents: String) -> [String: String] {
        var dict: [String: String] = [:]
        
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            
            dict[key] = value
        }
        
        return dict
    }
}

struct SupabaseConfig {
    let url: URL
    let anonKey: String
    
    static func load() -> SupabaseConfig? {
        // 1) Environment variables
        if let config = build(from: ProcessInfo.processInfo.environment) {
            return config
        }
        
        // 2) .env (auto-loaded from current working directory or app bundle resources)
        if let config = build(from: DotEnv.load()) {
            return config
        }
        
        // 3) Info.plist fallback
        if
            let dict = Bundle.main.infoDictionary,
            let urlString = dict["SUPABASE_URL"] as? String,
            let key = dict["SUPABASE_ANON_KEY"] as? String
        {
            return build(urlString: urlString, anonKey: key)
        }
        
        return nil
    }
    
    private static func build(from dict: [String: String]) -> SupabaseConfig? {
        build(urlString: dict["SUPABASE_URL"], anonKey: dict["SUPABASE_ANON_KEY"])
    }
    
    private static func build(urlString: String?, anonKey: String?) -> SupabaseConfig? {
        let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let anonKey = anonKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard
            let urlString,
            !urlString.isEmpty,
            let anonKey,
            !anonKey.isEmpty,
            let url = URL(string: urlString)
        else {
            return nil
        }
        
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let user: SupabaseUser?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
}

struct SupabaseUser: Codable {
    let id: String
    let email: String?
}

enum AuthState {
    case loggedOut
    case loading
    case authenticated(SupabaseSession)
}

enum AuthError: LocalizedError {
    case configurationMissing
    case invalidCredentials
    case network(String)
    
    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "缺少 Supabase 配置信息，请设置 SUPABASE_URL 和 SUPABASE_ANON_KEY。"
        case .invalidCredentials:
            return "邮箱或密码不正确。"
        case .network(let message):
            return message
        }
    }
}

class SupabaseAuthService {
    func buildGitHubOAuthURL(config: SupabaseConfig, redirectURL: URL) -> URL? {
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "github"),
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString)
        ]
        return components?.url
    }
    
    func refreshSession(refreshToken: String, config: SupabaseConfig) async throws -> SupabaseSession {
        let endpoint = config.url.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        
        guard let url = components?.url else {
            throw AuthError.network("无法拼接 Supabase 刷新地址。")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: String] = ["refresh_token": refreshToken]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.network("刷新失败：未获得有效响应。")
        }
        
        if (200..<300).contains(httpResponse.statusCode) {
            return try JSONDecoder().decode(SupabaseSession.self, from: data)
        } else {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.network("刷新失败：\(message)")
        }
    }
}

private struct StoredSession: Codable {
    let session: SupabaseSession
    let expiresAt: Date
}

@MainActor
class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var authState: AuthState = .loggedOut
    @Published var errorMessage: String?
    
    private let authService = SupabaseAuthService()
    private let config = SupabaseConfig.load()
    private var authSession: ASWebAuthenticationSession?
    private var sessionExpiry: Date?
    private let storageKey = "SupabaseStoredSession"
    
    override init() {
        super.init()
        Task { await restoreSessionIfPossible() }
    }
    
    func signInWithGitHub() {
        guard let config = config else {
            errorMessage = AuthError.configurationMissing.localizedDescription
            authState = .loggedOut
            return
        }
        
        errorMessage = nil
        authState = .loading
        
        let callbackScheme = "macstatus"
        guard let redirect = URL(string: "\(callbackScheme)://auth-callback"),
              let url = authService.buildGitHubOAuthURL(config: config, redirectURL: redirect) else {
            errorMessage = "无法构建 GitHub 登录链接。"
            authState = .loggedOut
            return
        }
        
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.authState = .loggedOut
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                DispatchQueue.main.async {
                    self.errorMessage = "登录未完成，请重试。"
                    self.authState = .loggedOut
                }
                return
            }
            
            self.handleOAuthCallback(url: callbackURL)
        }
        
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        authSession = session
        session.start()
    }
    
    func handleOAuthCallback(url: URL) {
        // Supabase 会把 token 信息放在 fragment 中
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            DispatchQueue.main.async {
                self.errorMessage = "未获取到登录凭证。"
                self.authState = .loggedOut
            }
            return
        }
        
        let pairs = fragment.split(separator: "&").map { pair -> (String, String)? in
            let parts = pair.split(separator: "=")
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                return (key, value)
            }
            return nil
        }.compactMap { $0 }
        
        var dict: [String: String] = [:]
        pairs.forEach { dict[$0.0] = $0.1 }
        
        guard let accessToken = dict["access_token"] else {
            DispatchQueue.main.async {
                self.errorMessage = "未获取到 access token。"
                self.authState = .loggedOut
            }
            return
        }
        
        let refreshToken = dict["refresh_token"]
        let tokenType = dict["token_type"]
        let expiresIn = dict["expires_in"].flatMap { Int($0) }
        let email = dict["user_email"] ?? JWT.claim(accessToken, key: "email")
        let userId = dict["user_id"] ?? JWT.claim(accessToken, key: "sub")
        
        let session = SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            user: SupabaseUser(id: userId ?? "", email: email)
        )
        
        let expiry = Date().addingTimeInterval(Double(expiresIn ?? 3600))
        saveSession(session, expiresAt: expiry)
        
        DispatchQueue.main.async {
            self.authState = .authenticated(session)
        }
    }
    
    func signOut() {
        errorMessage = nil
        authState = .loggedOut
        sessionExpiry = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }
    
    var isLoading: Bool {
        if case .loading = authState { return true }
        return false
    }
    
    var currentUserEmail: String {
        if case .authenticated(let session) = authState {
            return session.user?.email ?? "GitHub 登录"
        }
        return ""
    }
    
    var currentSession: SupabaseSession? {
        if case .authenticated(let session) = authState {
            return session
        }
        return nil
    }
    
    var supabaseConfig: SupabaseConfig? {
        return config
    }
    
    func ensureValidSession() async -> SupabaseSession? {
        guard let config = config else { return nil }
        
        if case .authenticated(let session) = authState {
            if let expiry = sessionExpiry, expiry.timeIntervalSinceNow > 60 {
                return session
            }
            
            if let refresh = session.refreshToken {
                do {
                    let newSession = try await authService.refreshSession(refreshToken: refresh, config: config)
                    let expiry = Date().addingTimeInterval(Double(newSession.expiresIn ?? 3600))
                    saveSession(newSession, expiresAt: expiry)
                    authState = .authenticated(newSession)
                    return newSession
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    authState = .loggedOut
                    sessionExpiry = nil
                    UserDefaults.standard.removeObject(forKey: storageKey)
                    return nil
                }
            }
        }
        return nil
    }
    
    private func restoreSessionIfPossible() async {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
              let config = config else { return }
        
        if stored.expiresAt.timeIntervalSinceNow > 60 {
            sessionExpiry = stored.expiresAt
            authState = .authenticated(stored.session)
            return
        }
        
        if let refresh = stored.session.refreshToken {
            do {
                let newSession = try await authService.refreshSession(refreshToken: refresh, config: config)
                let expiry = Date().addingTimeInterval(Double(newSession.expiresIn ?? 3600))
                saveSession(newSession, expiresAt: expiry)
                authState = .authenticated(newSession)
            } catch {
                authState = .loggedOut
                sessionExpiry = nil
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
    }
    
    private func saveSession(_ session: SupabaseSession, expiresAt: Date) {
        sessionExpiry = expiresAt
        let stored = StoredSession(session: session, expiresAt: expiresAt)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    // macOS 需要返回一个窗口用于展示认证会话
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

enum JWT {
    static func claim(_ token: String, key: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let data = Data(base64URLEncoded: String(parts[1])) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key] as? String
    }
}

extension Data {
    init?(base64URLEncoded input: String) {
        var base64 = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: base64)
    }
}
