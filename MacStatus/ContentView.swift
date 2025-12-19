import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var uploader: MetricsUploader
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var devicesModel = DevicesViewModel()
    @State private var showCopiedAlert: Bool = false
    @State private var selectedTab: Int = 0
    @AppStorage("MenuBarDisplayType") private var menuBarDisplayType: String = "none"
    @AppStorage("AppTheme") private var appTheme: String = "system"
    @AppStorage("AccentColorHex") private var accentColorHex: String = "#007AFF"
    
    // 统一的网格列定义
    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 320, maximum: 600), spacing: 20)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView
            
            // 导航栏
            navigationBar
            
            // 内容区域
            ZStack {
                switch selectedTab {
                case 0: dashboardView
                case 1: resourcesView
                case 2: processesView
                case 3: hardwareView
                case 4: securityView
                case 5: cloudView
                case 6: SettingsView(monitor: monitor)
                default: dashboardView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 底部操作栏
            footerView
        }
        .frame(minWidth: 400, minHeight: 600)
        .accentColor(Color(hex: accentColorHex) ?? .blue)
        .preferredColorScheme(appTheme == "light" ? .light : (appTheme == "dark" ? .dark : nil))
        .task {
            if authManager.isAuthenticated {
                await devicesModel.refresh(authManager: authManager)
            }
        }
        .alert("已复制到剪贴板", isPresented: $showCopiedAlert) {
            Button("好", role: .cancel) {}
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
            Text("Mac Status")
                    .font(.title2)
                    .fontWeight(.bold)
                
            if monitor.isCameraInUse {
                Image(systemName: "video.fill")
                    .foregroundColor(.red)
                    .help("摄像头正在被占用")
            }
                
                if monitor.isPowerSaveModeActive {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                        .help("智能省电模式已开启")
                }
            
            if monitor.isGameModeActive {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.orange)
                    .help("自动游戏模式已激活：已降低监控频率以确保性能")
                }
                
                Spacer()
            
                if authManager.isAuthenticated {
                    Text(authManager.currentUserEmail)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .background((Color(hex: accentColorHex) ?? .blue).opacity(0.1))
    }
    
    private var navigationBar: some View {
        HStack(spacing: 0) {
            navButton(index: 0, icon: "house.fill", label: "概览")
            navButton(index: 1, icon: "network", label: "资源")
            navButton(index: 2, icon: "cpu", label: "进程")
            navButton(index: 3, icon: "bolt.fill", label: "硬件")
            navButton(index: 4, icon: "shield.fill", label: "安全")
            navButton(index: 5, icon: "icloud.fill", label: "同步")
            navButton(index: 6, icon: "gearshape.fill", label: "设置")
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }
    
    private func navButton(index: Int, icon: String, label: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(selectedTab == index ? (Color(hex: accentColorHex) ?? .blue) : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab Views
    
    private var dashboardView: some View {
            ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                // AI 智能分析
                StatusCard(title: "AI 智能分析", icon: "brain.head.profile", color: .pink) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(monitor.aiInsight)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.pink.opacity(0.05))
                            .cornerRadius(10)
                        
                        HStack(spacing: 12) {
                            Button(action: { selectedTab = 6 }) {
                                Label("前往设置", systemImage: "arrow.right.circle").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { monitor.fetchAIInsight() }) {
                                Label("获取 AI 分析", systemImage: "sparkles").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                        }
                    }
                }
                
                // CPU 负载
                StatusCard(title: "CPU 负载", icon: "cpu", color: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("\(String(format: "%.1f", monitor.cpuUsage))%")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Spacer()
                            ProgressView(value: monitor.cpuUsage, total: 100).tint(.blue).frame(width: 80)
                        }
                        SparklineChart(data: monitor.cpuHistory, color: .blue, maxDataPoints: 60).frame(height: 40)
                    }
                }
                
                // 内存占用
                StatusCard(title: "内存占用", icon: "memorychip", color: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("\(String(format: "%.1f", monitor.memoryUsage))%")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Spacer()
                            Text("\(monitor.usedMemory)/\(monitor.totalMemory) GB").font(.caption).foregroundColor(.secondary)
                        }
                        ProgressView(value: monitor.memoryUsage, total: 100).tint(.purple)
                        SparklineChart(data: monitor.memoryHistory, color: .purple, maxDataPoints: 60).frame(height: 40)
                    }
                }
                
                // 菜单栏设置
                StatusCard(title: "实时显示设置", icon: "menubar.rectangle", color: .orange) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("指标", selection: $menuBarDisplayType) {
                            Text("仅图标").tag("none")
                            Text("CPU").tag("cpu")
                            Text("内存").tag("mem")
                            Text("网络").tag("net")
                        }.pickerStyle(.segmented)
                        
                        Toggle(isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "EnableMenuBarRotation") },
                            set: { UserDefaults.standard.set($0, forKey: "EnableMenuBarRotation") }
                        )) {
                            Text("自动轮播核心指标 (5s/次)").font(.system(size: 12))
                        }.toggleStyle(.checkbox)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
    }
    
    private var resourcesView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                StatusCard(title: "网络实时流量", icon: "arrow.up.arrow.down.circle", color: .mint) {
                    VStack(spacing: 12) {
                            HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(monitor.networkDownloadSpeed)").font(.system(size: 20, weight: .bold)) + Text(" MB/s").font(.caption)
                                Text("总下载: \(monitor.totalDownload)").font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer()
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(.mint.opacity(0.5))
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(monitor.networkUploadSpeed)").font(.system(size: 20, weight: .bold)) + Text(" MB/s").font(.caption)
                                Text("总上传: \(monitor.totalUpload)").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill").foregroundColor(.mint.opacity(0.5))
                        }
                        HStack(spacing: 12) {
                            Label(monitor.wifiSSID, systemImage: "wifi").font(.system(size: 10))
                            Spacer()
                            Label(monitor.networkLatency, systemImage: "waveform.path.ecg").font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                }
                
                StatusCard(title: "磁盘存取", icon: "internaldrive.fill", color: .green) {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: monitor.diskUsage, total: 100).tint(.green)
                        HStack {
                            Text("\(monitor.usedDisk)/\(monitor.totalDisk) GB").font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("\(Int(monitor.diskUsage))%").font(.caption).foregroundColor(.secondary)
                        }
                        Divider().padding(.vertical, 2)
                        VStack(spacing: 6) {
                            HStack {
                                Text("读取").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("\(monitor.diskReadSpeed) MB/s").font(.system(size: 12, weight: .semibold))
                            }
                            HStack {
                                Text("写入").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("\(monitor.diskWriteSpeed) MB/s").font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                }
                
                StatusCard(title: "活跃网络进程", icon: "arrow.up.arrow.down.circle.fill", color: .mint) {
                        VStack(spacing: 8) {
                        if monitor.topNetworkProcesses.isEmpty {
                            Text("正在采集数据...").font(.caption).foregroundColor(.secondary).padding()
                        } else {
                            ForEach(monitor.topNetworkProcesses.prefix(5)) { proc in
                                HStack {
                                    Text(proc.name).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    Text("\(String(format: "%.1f", proc.value)) \(proc.unit)").font(.system(size: 12, weight: .bold)).foregroundColor(.mint)
                                }.padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private var processesView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索活跃进程...", text: $monitor.processSearchText).textFieldStyle(.plain)
                if !monitor.processSearchText.isEmpty {
                    Button { monitor.processSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
            .padding([.horizontal, .top], 20)
            
            ScrollView {
                LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                    processGroup(title: "CPU 密集型进程", icon: "cpu.fill", color: .blue, data: monitor.topCPUProcesses)
                    processGroup(title: "内存密集型进程", icon: "memorychip.fill", color: .purple, data: monitor.topMemoryProcesses)
                }
                .padding(20)
            }
        }
    }
    
    private func processGroup(title: String, icon: String, color: Color, data: [ProcessInfoData]) -> some View {
        StatusCard(title: title, icon: icon, color: color) {
            VStack(alignment: .leading, spacing: 10) {
                let filteredProcs = data.filter { monitor.processSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(monitor.processSearchText) }
                if filteredProcs.isEmpty {
                    Text(monitor.processSearchText.isEmpty ? "采集数据中..." : "未找到匹配项").font(.caption).foregroundColor(.secondary).padding(.vertical, 10)
                } else {
                    ForEach(filteredProcs.prefix(8)) { proc in
                                HStack {
                            Button(action: { monitor.killProcess(pid: proc.pid) }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                            }.buttonStyle(.plain)
                            Text(proc.name).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                            Text("\(String(format: "%.1f", proc.value))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(color)
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
    }
    
    private var hardwareView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                StatusCard(title: "CPU 核心温度矩阵", icon: "square.grid.3x3.fill", color: .red) {
                    VStack(alignment: .leading, spacing: 12) {
                        if monitor.pCoreTemps.isEmpty && monitor.eCoreTemps.isEmpty {
                            Text("未检测到独立核心传感器 (仅 Apple Silicon 支持)").font(.caption).foregroundColor(.secondary)
                        } else {
                            if !monitor.pCoreTemps.isEmpty {
                                Text("性能核 (P-Cores)").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                                coreGrid(temps: monitor.pCoreTemps)
                            }
                            
                            if !monitor.eCoreTemps.isEmpty {
                                Text("能效核 (E-Cores)").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).padding(.top, 4)
                                coreGrid(temps: monitor.eCoreTemps)
                            }
                        }
                    }
                }
                
                StatusCard(title: "电池信息", icon: "battery.100", color: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(monitor.batteryLevel)%").font(.system(size: 24, weight: .bold))
                            Spacer()
                            Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100").foregroundColor(monitor.isCharging ? .yellow : .green).font(.title3)
                        }
                        ProgressView(value: Double(monitor.batteryLevel), total: 100).tint(monitor.batteryLevel < 20 ? .red : .green)
                        HStack {
                            Text("健康度: \(monitor.batteryHealth)%")
                            Spacer()
                            Text("循环: \(monitor.batteryCycles)")
                        }.font(.caption).foregroundColor(.secondary)
                        Text("实时功率: \(String(format: "%.1f", monitor.batteryPower)) W").font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                    }
                }
                
                StatusCard(title: "系统温度", icon: "thermometer", color: .red) {
                    VStack(spacing: 8) {
                        if monitor.temperatures.isEmpty {
                            Text("未检测到传感器").font(.caption).foregroundColor(.secondary)
                            } else {
                            ForEach(monitor.temperatures, id: \.name) { temp in
                                    HStack {
                                    Text(temp.name).font(.system(size: 12))
                                        Spacer()
                                    Text("\(String(format: "%.1f", temp.value))°C").font(.system(size: 12, weight: .bold)).foregroundColor(temperatureColor(temp.value))
                                }
                            }
                        }
                    }
                }
                
                StatusCard(title: "风扇状态", icon: "fan", color: .cyan) {
                    VStack(spacing: 8) {
                        if monitor.fans.isEmpty {
                            Text("此设备可能无风扇").font(.caption).foregroundColor(.secondary)
                            } else {
                            ForEach(monitor.fans, id: \.name) { fan in
                                    HStack {
                                    Text(fan.name).font(.system(size: 12))
                                        Spacer()
                                    Text("\(Int(fan.rpm)) RPM").font(.system(size: 12, weight: .bold))
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private var securityView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                StatusCard(title: "安全审计", icon: "lock.shield", color: .red) {
                    VStack(alignment: .leading, spacing: 12) {
                        securityRow(label: "SIP 状态", value: monitor.sipStatus, icon: "shield.checkered")
                        securityRow(label: "防火墙", value: monitor.firewallStatus, icon: "wall.fill")
                        securityRow(label: "磁盘加密", value: monitor.fileVaultStatus, icon: "lock.square.stack.fill")
                    }
                }
                
                StatusCard(title: "系统运行", icon: "timer", color: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(monitor.uptime).font(.system(size: 24, weight: .bold, design: .monospaced))
                            Spacer()
                        }
                        Text("自上次重启以来的时长").font(.caption).foregroundColor(.secondary)
                    }
                }
                
                StatusCard(title: "维护工具", icon: "wrench.and.screwdriver.fill", color: .secondary) {
                    VStack(spacing: 12) {
                        Button(action: { monitor.performQuickCleanup() }) {
                            Label("释放内存 (Purge)", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        
                        Button(action: {
                            let summary = monitor.buildDeviceSummary()
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(summary, forType: .string)
                            showCopiedAlert = true
                        }) {
                            Label("复制诊断报告", systemImage: "doc.text").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func securityRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.secondary).frame(width: 20)
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(value.contains("开启") || value.contains("有效") ? .green : .red)
        }
    }
    
    private var cloudView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                StatusCard(title: "多设备同步", icon: "laptopcomputer", color: .indigo) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("设备数量: \(devicesModel.devices.count)").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button("刷新") { Task { await devicesModel.refresh(authManager: authManager) } }.buttonStyle(.bordered).controlSize(.small)
                        }
                        if devicesModel.isLoading { ProgressView().scaleEffect(0.8) }
                                ForEach(devicesModel.devices) { device in
                                    DeviceRowView(device: device, devicesModel: devicesModel)
                        }
                        Button(action: { openWebPanel() }) {
                            Label("管理 Web 控制台", systemImage: "globe").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }
                }
                
                StatusCard(title: "上报指标", icon: "arrow.up.icloud", color: .teal) {
                    VStack(alignment: .leading, spacing: 10) {
                        上报行(label: "最后尝试", value: uploader.lastUploadAttemptAt.map { formatDate($0) } ?? "从未")
                        上报行(label: "最后成功", value: uploader.lastUploadSucceededAt.map { formatDate($0) } ?? "从未")
                            if let error = uploader.lastUploadErrorMessage {
                            Text(error).font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
                        }
                        Button(action: { monitor.exportHistoryToCSV() }) {
                            Label("导出历史 CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).padding(.top, 4)
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func 上报行(label: String, value: String) -> some View {
            HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }
    
    private var footerView: some View {
        HStack {
            Button(action: { authManager.signOut() }) {
                Text("退出登录").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("退出应用").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    
    // MARK: - Helpers
    
    private func temperatureColor(_ temp: Double) -> Color {
        if temp > 80 { return .red }
        else if temp > 60 { return .orange }
        else { return .green }
    }
    
    private func coreGrid(temps: [TemperatureInfo]) -> some View {
        let cols = [GridItem(.adaptive(minimum: 65, maximum: 100), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(temps, id: \.name) { temp in
                VStack(spacing: 4) {
                    Text(temp.name.replacingOccurrences(of: "-Core", with: ""))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("\(Int(temp.value))°")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(temperatureColor(temp.value))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }
    
    private func copyAllInfo() {
        let text = buildDiagnosticsText()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func openWebPanel() {
        guard let url = URL(string: "https://mac.mydaily.cloud/") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func buildDiagnosticsText() -> String {
        var lines: [String] = []
        lines.append("MacStatus 诊断报告 [\(formatDate(Date()))]")
        let device = DeviceManager.shared
        lines.append("设备: \(device.deviceName) (\(device.model)) - \(device.osVersion)")
        lines.append("CPU: \(String(format: "%.1f", monitor.cpuUsage))% | 内存: \(monitor.usedMemory)/\(monitor.totalMemory) GB")
        lines.append("磁盘: \(monitor.diskUsage)% | 网络: ↓\(monitor.networkDownloadSpeed) / ↑\(monitor.networkUploadSpeed) MB/s")
        lines.append("电池: \(monitor.batteryLevel)% (\(monitor.isCharging ? "充电中" : "放电中"))")
        return lines.joined(separator: "\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

// MARK: - Helper Views & Styles

struct TransparentGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 30, height: 30)
                Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading) // 统一最小高度，防止“狗啃”感
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

struct DeviceRowView: View {
    let device: MacStatusDevice
    @ObservedObject var devicesModel: DevicesViewModel
    @EnvironmentObject var authManager: AuthManager
    
    @State private var isEditing = false
    @State private var newName = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        let isCurrent = device.device_uuid.lowercased() == DeviceManager.shared.deviceUUID.uuidString.lowercased()
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                if isEditing {
                    TextField("输入设备名称", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    
                    Button {
                        Task {
                            await devicesModel.renameDevice(id: device.id, newName: newName, authManager: authManager)
                            isEditing = false
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        isEditing = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(device.device_name ?? device.device_uuid)
                                .font(.subheadline)
                                .fontWeight(isCurrent ? .semibold : .regular)
                            if isCurrent {
                                Text("(当前)")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        Text(device.model ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button {
                            openWebDashboard(for: device)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("在 Web 面板查看")

                        Button {
                            newName = device.device_name ?? ""
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("重命名设备")
                        
                        if !isCurrent {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("删除设备记录")
                        }
                    }
                }
            }
            
            HStack {
                Text("最后在线: \(device.last_seen_at ?? "未知")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Divider()
                .padding(.vertical, 4)
        }
        .confirmationDialog("确定删除该设备记录吗？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                Task {
                    await devicesModel.deleteDevice(id: device.id, authManager: authManager)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，该设备的历史监控数据将无法在云端查看。")
        }
    }
    
    private func openWebDashboard(for device: MacStatusDevice) {
        let baseUrl = "https://mac.mydaily.cloud/"
        let urlString = "\(baseUrl)?device=\(device.device_uuid.lowercased())"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
