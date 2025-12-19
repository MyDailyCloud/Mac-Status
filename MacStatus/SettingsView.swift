import SwiftUI

// Hex 颜色支持扩展
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
    
    func toHex() -> String? {
        let uic = NSColor(self)
        guard let rgbColor = uic.usingColorSpace(.deviceRGB) else { return nil }
        
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct SettingsView: View {
    @AppStorage("MonitoringInterval") private var monitoringInterval: Double = 1.0
    @AppStorage("UploadInterval") private var uploadInterval: Double = 5.0
    @AppStorage("MenuBarDisplayType") private var menuBarDisplayType: String = "none"
    @AppStorage("AI_BaseURL") private var aiBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("AI_APIKey") private var aiAPIKey: String = ""
    @AppStorage("AI_ModelName") private var aiModelName: String = "gpt-3.5-turbo"
    
    var monitor: SystemMonitor
    
    var body: some View {
        TabView {
            GeneralSettingsView(monitoringInterval: $monitoringInterval, monitor: monitor)
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
            
            CloudSettingsView(uploadInterval: $uploadInterval)
                .tabItem {
                    Label("云端同步", systemImage: "cloud")
                }
            
            AppearanceSettingsView(menuBarDisplayType: $menuBarDisplayType)
                .tabItem {
                    Label("外观", systemImage: "paintbrush")
                }
            
            AISettingsView(baseURL: $aiBaseURL, apiKey: $aiAPIKey, modelName: $aiModelName)
                .tabItem {
                    Label("AI 分析", systemImage: "brain")
                }
            
            AlertSettingsView()
                .tabItem {
                    Label("告警阈值", systemImage: "bell.badge")
                }
        }
        .padding()
    }
}

struct AlertSettingsView: View {
    @AppStorage("Threshold_CPUTemp") private var cpuTemp: Double = 90.0
    @AppStorage("Threshold_MemUsage") private var memUsage: Double = 95.0
    @AppStorage("Threshold_DiskFree") private var diskFree: Double = 5.0
    
    var body: some View {
        Form {
            Section {
                VStack {
                    HStack {
                        Text("CPU 温度告警阈值")
                        Spacer()
                        Text("\(Int(cpuTemp))°C")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $cpuTemp, in: 60...100, step: 5)
                }
                
                VStack {
                    HStack {
                        Text("内存使用率告警阈值")
                        Spacer()
                        Text("\(Int(memUsage))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $memUsage, in: 70...99, step: 1)
                }
                
                VStack {
                    HStack {
                        Text("磁盘剩余空间告警 (GB)")
                        Spacer()
                        Text("\(Int(diskFree)) GB")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $diskFree, in: 1...50, step: 1)
                }
            } header: {
                Text("自定义告警触发点")
            }
        }
        .padding()
    }
}

struct AISettingsView: View {
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var modelName: String
    
    var body: some View {
        Form {
            Section {
                TextField("API Base URL", text: $baseURL)
                SecureField("API Key", text: $apiKey)
                TextField("模型名称", text: $modelName)
                
                Text("配置 OpenAI 兼容的 API 以启用 AI 性能分析功能。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } header: {
                Text("AI 服务配置")
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Binding var monitoringInterval: Double
    var monitor: SystemMonitor
    @StateObject private var launchManager = LaunchManager.shared
    @AppStorage("EnableAlerts") private var enableAlerts: Bool = true
    @AppStorage("EnableSmartPowerSave") private var enableSmartPowerSave: Bool = true
    @AppStorage("EnableAutoGameMode") private var enableAutoGameMode: Bool = true
    
    let intervals = [0.5, 1.0, 2.0, 5.0]
    
    var body: some View {
        Form {
            Section {
                Toggle("开机时自动启动", isOn: Binding(
                    get: { launchManager.isLaunchAtLoginEnabled },
                    set: { _ in launchManager.toggleLaunchAtLogin() }
                ))
                
                Toggle("开启异常告警通知", isOn: $enableAlerts)
                
                Toggle("智能省电模式", isOn: $enableSmartPowerSave)
                
                if enableSmartPowerSave {
                    Text("当电池电量低于 20% 时，自动将采样率降低至 5s 以节省电量。")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.leading, 20)
                }

                Toggle("自动游戏/高负载模式", isOn: $enableAutoGameMode)
                
                if enableAutoGameMode {
                    Text("检测到全屏应用（如游戏、视频）时，自动将监控采样率降低至 10s，确保前台流畅。")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.leading, 20)
                }
                
                Picker("监控采样频率", selection: $monitoringInterval) {
                    Text("极高 (0.5s)").tag(0.5)
                    Text("高 (1s)").tag(1.0)
                    Text("中 (2s)").tag(2.0)
                    Text("低 (5s)").tag(5.0)
                }
                .onChange(of: monitoringInterval) { newValue in
                    monitor.updateInterval(newValue)
                }
                
                Text("较低的频率可以减少 CPU 占用，适合电池供电时使用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("性能设置")
            }
        }
        .padding()
    }
}

struct CloudSettingsView: View {
    @Binding var uploadInterval: Double
    
    var body: some View {
        Form {
            Section {
                Picker("数据上报间隔", selection: $uploadInterval) {
                    Text("实时 (5s)").tag(5.0)
                    Text("频繁 (10s)").tag(10.0)
                    Text("标准 (30s)").tag(30.0)
                    Text("稀疏 (60s)").tag(60.0)
                    Text("仅监控 (不上传)").tag(999999.0)
                }
                
                Text("将系统状态快照异步上报至 Supabase。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("云端同步设置")
            }
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @Binding var menuBarDisplayType: String
    @AppStorage("AppTheme") private var appTheme: String = "system"
    @AppStorage("AccentColorHex") private var accentColorHex: String = "#007AFF"
    
    var body: some View {
        Form {
            Section {
                Picker("应用主题", selection: $appTheme) {
                    Text("系统默认").tag("system")
                    Text("浅色模式").tag("light")
                    Text("深色模式").tag("dark")
                }
                
                ColorPicker("应用强调色", selection: Binding(
                    get: { Color(hex: accentColorHex) ?? .blue },
                    set: { accentColorHex = $0.toHex() ?? "#007AFF" }
                ))
            } header: {
                Text("全局主题设置")
            }
            
            Section {
                Picker("菜单栏显示指标", selection: $menuBarDisplayType) {
                    Text("仅图标").tag("none")
                    Text("CPU 使用率").tag("cpu")
                    Text("内存使用率").tag("mem")
                    Text("网络下载速度").tag("net")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("菜单栏设置")
            }
        }
        .padding()
    }
}

