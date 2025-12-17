import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var uploader: MetricsUploader
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var devicesModel = DevicesViewModel()
    @State private var showCopiedAlert: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                Text("系统状态监控")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if authManager.isAuthenticated {
                    Text(authManager.currentUserEmail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        openPanel()
                    } label: {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.borderless)
                    .help("打开 Web 面板")
                }
                Button {
                    copyAllInfo()
                    showCopiedAlert = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制所有信息")
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            
            ScrollView {
                VStack(spacing: 16) {
                    // CPU信息
                    StatusCard(
                        title: "CPU使用率",
                        icon: "cpu",
                        color: .blue
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: monitor.cpuUsage, total: 100)
                                .tint(.blue)
                            Text("\(String(format: "%.1f", monitor.cpuUsage))%")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // 内存信息
                    StatusCard(
                        title: "内存使用",
                        icon: "memorychip",
                        color: .purple
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: monitor.memoryUsage, total: 100)
                                .tint(.purple)
                            HStack {
                                Text("\(String(format: "%.1f", monitor.memoryUsage))%")
                                    .font(.title)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(monitor.usedMemory) / \(monitor.totalMemory) GB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 硬盘使用量
                    StatusCard(
                        title: "硬盘使用",
                        icon: "internaldrive.fill",
                        color: .green
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if monitor.totalDisk == "N/A" || monitor.usedDisk == "N/A" {
                                Text("N/A")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView(value: monitor.diskUsage, total: 100)
                                    .tint(.green)
                                HStack {
                                    Text("\(String(format: "%.1f", monitor.diskUsage))%")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(monitor.usedDisk) / \(monitor.totalDisk) GB")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // 硬盘读写
                    StatusCard(
                        title: "硬盘读写",
                        icon: "internaldrive",
                        color: .green
                    ) {
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("读取")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(monitor.diskReadSpeed)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("MB/s")
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                            }
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("写入")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(monitor.diskWriteSpeed)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("MB/s")
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                            }
                        }
                    }
                    
                    // 网络上下行
                    StatusCard(
                        title: "网络",
                        icon: "network",
                        color: .mint
                    ) {
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("下载")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(monitor.networkDownloadSpeed)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("MB/s")
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.mint)
                                    .font(.title2)
                            }
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("上传")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(monitor.networkUploadSpeed)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("MB/s")
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.cyan)
                                    .font(.title2)
                            }
                        }
                    }
                    
                    // 温度信息
                    StatusCard(
                        title: "系统温度",
                        icon: "thermometer",
                        color: .red
                    ) {
                        VStack(spacing: 8) {
                            ForEach(monitor.temperatures, id: \.name) { temp in
                                HStack {
                                    Text(temp.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.1f", temp.value))°C")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(temperatureColor(temp.value))
                                }
                            }
                        }
                    }
                    
                    // 风扇信息
                    StatusCard(
                        title: "风扇转速",
                        icon: "fan",
                        color: .cyan
                    ) {
                        VStack(spacing: 8) {
                            ForEach(monitor.fans, id: \.name) { fan in
                                HStack {
                                    Text(fan.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(fan.rpm)) RPM")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                    
                    StatusCard(
                        title: "我的设备",
                        icon: "laptopcomputer",
                        color: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("当前设备：\(DeviceManager.shared.deviceName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("刷新") {
                                    Task { await devicesModel.refresh(authManager: authManager) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            if devicesModel.isLoading {
                                ProgressView()
                            }
                            
                            if let error = devicesModel.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if devicesModel.devices.isEmpty, !devicesModel.isLoading, devicesModel.errorMessage == nil {
                                Text("暂无设备记录。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(devicesModel.devices) { device in
                                    let isCurrent = device.device_uuid.lowercased() == DeviceManager.shared.deviceUUID.uuidString.lowercased()
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.device_name ?? device.device_uuid)
                                                .font(.subheadline)
                                                .fontWeight(isCurrent ? .semibold : .regular)
                                            Text(device.model ?? "")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(device.last_seen_at ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    
                    StatusCard(
                        title: "上传状态",
                        icon: "arrow.up.circle",
                        color: .teal
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let last = uploader.lastUploadAttemptAt {
                                Text("上次尝试：\(formatDate(last))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("尚未尝试上传。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let last = uploader.lastUploadSucceededAt {
                                Text("上次成功：\(formatDate(last))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let error = uploader.lastUploadErrorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else if uploader.lastUploadAttemptAt != nil {
                                Text("最近一次上传：成功")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            
            // 底部按钮
            HStack {
                Button(action: {
                    authManager.signOut()
                }) {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("退出")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
        }
        .task {
            if authManager.isAuthenticated {
                await devicesModel.refresh(authManager: authManager)
            }
        }
        .alert("已复制到剪贴板", isPresented: $showCopiedAlert) {
            Button("好", role: .cancel) {}
        }
    }
    
    func temperatureColor(_ temp: Double) -> Color {
        if temp > 80 {
            return .red
        } else if temp > 60 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func copyAllInfo() {
        let text = buildDiagnosticsText()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func openPanel() {
        guard let url = URL(string: "https://mac.mydaily.cloud/") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func buildDiagnosticsText() -> String {
        var lines: [String] = []
        lines.append("MacStatus 诊断信息")
        lines.append("生成时间: \(formatDate(Date()))")
        lines.append("")
        
        let device = DeviceManager.shared
        lines.append("[设备]")
        lines.append("deviceUUID: \(device.deviceUUID.uuidString)")
        lines.append("deviceName: \(device.deviceName)")
        lines.append("model: \(device.model)")
        lines.append("osVersion: \(device.osVersion)")
        lines.append("appVersion: \(device.appVersion)")
        lines.append("")
        
        lines.append("[Supabase]")
        if let cfg = authManager.supabaseConfig {
            lines.append("url: \(cfg.url.absoluteString)")
            lines.append("anonKey: \(redact(cfg.anonKey))")
        } else {
            lines.append("config: missing")
        }
        lines.append("")
        
        lines.append("[登录]")
        lines.append("isAuthenticated: \(authManager.isAuthenticated)")
        lines.append("email: \(authManager.currentUserEmail)")
        if let session = authManager.currentSession {
            let sessionUserId = session.user?.id
            let jwtUserId = JWT.claim(session.accessToken, key: "sub")
            let jwtEmail = JWT.claim(session.accessToken, key: "email")
            lines.append("session.user.id: \(sessionUserId?.isEmpty == false ? sessionUserId! : "(empty)")")
            lines.append("jwt.sub: \(jwtUserId ?? "(nil)")")
            lines.append("jwt.email: \(jwtEmail ?? "(nil)")")
            lines.append("accessToken: \(redact(session.accessToken))")
            lines.append("refreshToken: \(session.refreshToken.map(redact) ?? "(nil)")")
            lines.append("expiresIn: \(session.expiresIn.map(String.init) ?? "(nil)")")
        } else {
            lines.append("session: nil")
        }
        lines.append("")
        
        lines.append("[监控]")
        lines.append("cpuUsage: \(String(format: "%.1f", monitor.cpuUsage))%")
        lines.append("memoryUsage: \(String(format: "%.1f", monitor.memoryUsage))% (\(monitor.usedMemory)/\(monitor.totalMemory) GB)")
        if monitor.totalDisk == "N/A" || monitor.usedDisk == "N/A" {
            lines.append("diskUsage: N/A")
        } else {
            lines.append("diskUsage: \(String(format: "%.1f", monitor.diskUsage))% (\(monitor.usedDisk)/\(monitor.totalDisk) GB)")
        }
        lines.append("disk: read \(monitor.diskReadSpeed) MB/s, write \(monitor.diskWriteSpeed) MB/s")
        lines.append("network: down \(monitor.networkDownloadSpeed) MB/s, up \(monitor.networkUploadSpeed) MB/s")
        if !monitor.temperatures.isEmpty {
            lines.append("temperatures:")
            for t in monitor.temperatures {
                lines.append("  - \(t.name): \(String(format: "%.1f", t.value))°C")
            }
        }
        if !monitor.fans.isEmpty {
            lines.append("fans:")
            for f in monitor.fans {
                lines.append("  - \(f.name): \(Int(f.rpm)) RPM")
            }
        }
        lines.append("")
        
        lines.append("[设备注册/列表]")
        lines.append("devices.count: \(devicesModel.devices.count)")
        if let err = devicesModel.errorMessage {
            lines.append("devices.error: \(err)")
        }
        for d in devicesModel.devices.prefix(10) {
            lines.append("  - \(d.device_name ?? d.device_uuid) (\(d.device_uuid)) last_seen_at=\(d.last_seen_at ?? "")")
        }
        lines.append("")
        
        lines.append("[上传]")
        if let t = uploader.lastUploadAttemptAt {
            lines.append("lastAttemptAt: \(formatDate(t))")
        } else {
            lines.append("lastAttemptAt: (nil)")
        }
        if let t = uploader.lastUploadSucceededAt {
            lines.append("lastSucceededAt: \(formatDate(t))")
        } else {
            lines.append("lastSucceededAt: (nil)")
        }
        if let err = uploader.lastUploadErrorMessage {
            lines.append("lastError: \(err)")
        } else {
            lines.append("lastError: (nil)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func redact(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return "[redacted]" }
        let start = trimmed.prefix(6)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: date)
    }
}

struct StatusCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
