import Foundation
import Combine
import IOKit
import IOKit.ps
import Darwin
import CoreWLAN
import AVFoundation
import SwiftUI

struct MetricsSnapshot: Codable {
    let cpuUsage: Double
    let memoryUsage: Double
    let usedMemoryGB: Double
    let totalMemoryGB: Double
    let diskUsage: Double
    let diskUsedGB: Double
    let diskTotalGB: Double
    let diskReadSpeedMBps: Double
    let diskWriteSpeedMBps: Double
    let networkDownloadSpeedMBps: Double
    let networkUploadSpeedMBps: Double
    let batteryLevel: Int
    let isCharging: Bool
    let batteryHealth: Int
    let batteryCycles: Int
    let timestamp: Date
}

class SystemMonitor: ObservableObject {
    // UI 数据属性 (@Published)
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var usedMemory: String = "0.0"
    @Published var totalMemory: String = "0.0"
    @Published var diskUsage: Double = 0
    @Published var usedDisk: String = "N/A"
    @Published var totalDisk: String = "N/A"
    @Published var diskReadSpeed: String = "0.0"
    @Published var diskWriteSpeed: String = "0.0"
    @Published var networkDownloadSpeed: String = "0.0"
    @Published var networkUploadSpeed: String = "0.0"
    @Published var totalDownload: String = "0.0"
    @Published var totalUpload: String = "0.0"
    @Published var publicIP: String = "正在获取..."
    @Published var wifiSSID: String = "未连接"
    @Published var wifiRSSI: Int = 0
    @Published var networkLatency: String = "--- ms"
    @Published var uptime: String = "0h 0m"
    @Published var diskHealth: String = "100%"
    @Published var batteryPower: Double = 0
    @Published var isCameraInUse: Bool = false
    @Published var isMicInUse: Bool = false
    @Published var sipStatus: String = "未知"
    @Published var firewallStatus: String = "未知"
    @Published var fileVaultStatus: String = "未知"
    @Published var aiInsight: String = "点击按钮开始 AI 分析..."
    @Published var menuBarColor: Color = .primary
    @Published var themeAccentColor: Color = .blue
    
    @Published var temperatures: [TemperatureInfo] = []
    @Published var pCoreTemps: [TemperatureInfo] = []
    @Published var eCoreTemps: [TemperatureInfo] = []
    @Published var fans: [FanInfo] = []
    @Published var processSearchText: String = ""
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var batteryHealth: Int = 100
    @Published var batteryCycles: Int = 0
    @Published var powerSource: String = "Unknown"
    @Published var topCPUProcesses: [ProcessInfoData] = []
    @Published var topMemoryProcesses: [ProcessInfoData] = []
    @Published var topNetworkProcesses: [ProcessInfoData] = []
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var fullHistory: [MetricsSnapshot] = []
    @Published var isPowerSaveModeActive: Bool = false
    @Published var isGameModeActive: Bool = false
    
    // 内部控制
    private var timer: Timer?
    private let monitoringQueue = DispatchQueue(label: "com.macstatus.monitoring", qos: .userInitiated)
    private(set) var isRunning: Bool = false
    private let maxHistoryPoints = 60
    private let maxFullHistoryPoints = 1000
    
    // 采集状态记录
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0
    private var previousDiskRead: UInt64 = 0
    private var previousDiskWrite: UInt64 = 0
    private var previousTime: Date = Date()
    private var hasDiskBaseline: Bool = false
    private var previousNetIn: UInt64 = 0
    private var previousNetOut: UInt64 = 0
    private var hasNetworkBaseline: Bool = false
    private var previousNetworkTime: Date = Date()
    private var totalNetIn: UInt64 = 0
    private var totalNetOut: UInt64 = 0
    private var monitoringInterval: TimeInterval = 1.0
    private var lastAlertTime: [String: Date] = [:]
    private let alertCooldown: TimeInterval = 300
    private var slowUpdateCounter: Int = 30
    private var mediumUpdateCounter: Int = 5
    private var lastMenuBarRotationTime: Date = Date()
    private var menuBarRotationIndex: Int = 0
    
    // 临时存储变量，用于同步到 Published
    private var tempPCoreData: [TemperatureInfo] = []
    private var tempECoreData: [TemperatureInfo] = []
    
    var onMetricsUpdate: ((MetricsSnapshot) -> Void)?
    
    init(autoStart: Bool = true) {
        self.monitoringInterval = UserDefaults.standard.double(forKey: "MonitoringInterval")
        if self.monitoringInterval < 0.5 { self.monitoringInterval = 1.0 }
        if autoStart { self.startMonitoring() }
        self.fetchPublicIP()
        NotificationCenter.default.addObserver(self, selector: #selector(handlePowerSourceChange), name: NSNotification.Name(rawValue: kIOPSNotifyPowerSource), object: nil)
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handlePowerSourceChange() {
        monitoringQueue.async { [weak self] in
            self?.updateBatteryStats()
            self?.checkPowerSaveMode()
        }
    }
    
    func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true
        restartTimer()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func updateInterval(_ newInterval: TimeInterval) {
        guard newInterval != self.monitoringInterval else { return }
        self.monitoringInterval = newInterval
        UserDefaults.standard.set(newInterval, forKey: "MonitoringInterval")
        if self.isRunning { self.restartTimer() }
    }

    private func restartTimer() {
        timer?.invalidate()
        let autoGameMode = UserDefaults.standard.bool(forKey: "EnableAutoGameMode")
        let effectiveInterval: TimeInterval
        
        if isPowerSaveModeActive {
            effectiveInterval = max(monitoringInterval, 5.0)
        } else if autoGameMode && isGameModeActive {
            effectiveInterval = max(monitoringInterval, 10.0) // 游戏模式下极大降低频率
        } else {
            effectiveInterval = monitoringInterval
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            self?.monitoringQueue.async {
                self?.updateAllStats()
            }
        }
    }
    
    private func updateAllStats() {
        // --- 1. 高频数据采集 (Off Main Thread) ---
        let cpu = collectCPUUsage()
        let mem = collectMemoryUsage()
        let net = collectNetworkStats()
        let temps = collectTemperatures()
        let fanList = collectFans()
        
        // --- 2. 中低频任务逻辑 ---
        var batteryData: (level: Int, charging: Bool, source: String, cycles: Int, health: Int, power: Double)?
        var topProcs: (cpu: [ProcessInfoData], mem: [ProcessInfoData])?
        var privacyCam: Bool?
        var latency: String?
        var wifi: (ssid: String, rssi: Int)?
        var gameMode: Bool?
        
        if mediumUpdateCounter >= 5 {
            mediumUpdateCounter = 0
            batteryData = collectBatteryStats()
            topProcs = collectTopProcesses()
            privacyCam = collectPrivacyStatus()
            latency = collectNetworkLatency()
            wifi = collectWifiStats()
            gameMode = collectGameModeStatus()
        } else {
            mediumUpdateCounter += 1
        }
        
        var diskUsageData: (usage: Double, used: String, total: String)?
        var diskHealthVal: String?
        var security: (sip: String, fw: String, fv: String)?
        var sysUptime: String?
        var topNetProcs: [ProcessInfoData]?
        
        if slowUpdateCounter >= 30 {
            slowUpdateCounter = 0
            diskUsageData = collectDiskUsage()
            diskHealthVal = collectDiskHealth()
            security = collectSecurityStatus()
            sysUptime = collectSystemUptime()
            topNetProcs = collectTopNetworkProcesses()
        } else {
            slowUpdateCounter += 1
        }

        // --- 3. 统一 UI 更新 (Single Main Thread Dispatch) ---
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 高频更新
            self.cpuUsage = cpu
            self.memoryUsage = mem.usage
            self.usedMemory = mem.used
            self.totalMemory = mem.total
            self.networkDownloadSpeed = net.down
            self.networkUploadSpeed = net.up
            self.totalDownload = net.totalDown
            self.totalUpload = net.totalUp
            self.temperatures = temps
            self.pCoreTemps = self.tempPCoreData
            self.eCoreTemps = self.tempECoreData
            self.fans = fanList
            
            // 中频更新
            if let b = batteryData {
                self.batteryLevel = b.level
                self.isCharging = b.charging
                self.powerSource = b.source
                self.batteryCycles = b.cycles
                self.batteryHealth = b.health
                self.batteryPower = b.power
            }
            if let tp = topProcs {
                self.topCPUProcesses = tp.cpu
                self.topMemoryProcesses = tp.mem
            }
            if let pc = privacyCam { self.isCameraInUse = pc }
            if let lat = latency { self.networkLatency = lat }
            if let w = wifi { self.wifiSSID = w.ssid; self.wifiRSSI = w.rssi }
            if let gm = gameMode { 
                if self.isGameModeActive != gm {
                    self.isGameModeActive = gm
                    self.restartTimer() // 模式切换，重置计时器
                }
            }
            
            // 低频更新
            if let du = diskUsageData {
                self.diskUsage = du.usage
                self.usedDisk = du.used
                self.totalDisk = du.total
            }
            if let dh = diskHealthVal { self.diskHealth = dh }
            if let s = security {
                self.sipStatus = s.sip
                self.firewallStatus = s.fw
                self.fileVaultStatus = s.fv
            }
            if let up = sysUptime { self.uptime = up }
            if let tnp = topNetProcs { self.topNetworkProcesses = tnp }
            
            // 历史记录
            self.cpuHistory.append(self.cpuUsage)
            if self.cpuHistory.count > self.maxHistoryPoints { self.cpuHistory.removeFirst() }
            self.memoryHistory.append(self.memoryUsage)
            if self.memoryHistory.count > self.maxHistoryPoints { self.memoryHistory.removeFirst() }
            
            // 菜单栏颜色与告警
            self.updateMenuBarUI()
            self.processAlerts()
            
            // 生成快照
            let snapshot = MetricsSnapshot(
                cpuUsage: self.cpuUsage, memoryUsage: self.memoryUsage,
                usedMemoryGB: Double(self.usedMemory) ?? 0, totalMemoryGB: Double(self.totalMemory) ?? 0,
                diskUsage: self.diskUsage, diskUsedGB: Double(self.usedDisk) ?? 0, diskTotalGB: Double(self.totalDisk) ?? 0,
                diskReadSpeedMBps: Double(self.diskReadSpeed) ?? 0, diskWriteSpeedMBps: Double(self.diskWriteSpeed) ?? 0,
                networkDownloadSpeedMBps: Double(self.networkDownloadSpeed) ?? 0, networkUploadSpeedMBps: Double(self.networkUploadSpeed) ?? 0,
                batteryLevel: self.batteryLevel, isCharging: self.isCharging,
                batteryHealth: self.batteryHealth, batteryCycles: self.batteryCycles,
                timestamp: Date()
            )
            self.fullHistory.append(snapshot)
            if self.fullHistory.count > self.maxFullHistoryPoints { self.fullHistory.removeFirst() }
            self.onMetricsUpdate?(snapshot)
        }
        
        // 磁盘速度需要独立的时间戳计算
        updateDiskSpeeds()
    }
    
    private func collectCPUUsage() -> Double {
        var numCPUInfo: mach_msg_type_number_t = 0
        var numProcessors: natural_t = 0
        var cpuInfo: processor_info_array_t!
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numProcessors, &cpuInfo, &numCPUInfo)
        if result == KERN_SUCCESS {
            var avg: Double = 0
            if let prevInfo = previousCPUInfo {
                var totalUsage: Double = 0
            for i in 0..<Int(numProcessors) {
                    let base = i * Int(CPU_STATE_MAX)
                    let u = cpuInfo[Int(CPU_STATE_USER) + base] - prevInfo[Int(CPU_STATE_USER) + base]
                    let s = cpuInfo[Int(CPU_STATE_SYSTEM) + base] - prevInfo[Int(CPU_STATE_SYSTEM) + base]
                    let id = cpuInfo[Int(CPU_STATE_IDLE) + base] - prevInfo[Int(CPU_STATE_IDLE) + base]
                    let n = cpuInfo[Int(CPU_STATE_NICE) + base] - prevInfo[Int(CPU_STATE_NICE) + base]
                    let tot = Double(u + s + id + n)
                    if tot > 0 { totalUsage += Double(u + s + n) / tot }
                }
                avg = (totalUsage / Double(numProcessors)) * 100
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), vm_size_t(Int(previousCPUInfoCount) * MemoryLayout<integer_t>.size))
            }
            previousCPUInfo = cpuInfo
            previousCPUInfoCount = numCPUInfo
            return avg
        }
        return 0
    }

    private func collectMemoryUsage() -> (usage: Double, used: String, total: String) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let res = withUnsafeMutablePointer(to: &stats) { 
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { 
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) 
            }
        }
        if res == KERN_SUCCESS {
            let used = UInt64(stats.active_count + stats.wire_count) * UInt64(vm_kernel_page_size)
            let total = ProcessInfo.processInfo.physicalMemory
            return (Double(used) / Double(total) * 100, 
                    String(format: "%.1f", Double(used) / 1_073_741_824), 
                    String(format: "%.1f", Double(total) / 1_073_741_824))
        }
        return (0, "0.0", "0.0")
    }

    private func collectNetworkStats() -> (down: String, up: String, totalDown: String, totalUp: String) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return ("0.00", "0.00", "0.0 MB", "0.0 MB") }
        defer { freeifaddrs(addrs) }
        var ti: UInt64 = 0; var to: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let curr = ptr {
            let flags = Int32(curr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0, 
               let addr = curr.pointee.ifa_addr, addr.pointee.sa_family == AF_LINK,
               let data = curr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                ti += UInt64(data.pointee.ifi_ibytes); to += UInt64(data.pointee.ifi_obytes)
            }
            ptr = curr.pointee.ifa_next
        }
        let now = Date(); let dt = now.timeIntervalSince(previousNetworkTime)
        var dStr = "0.00", uStr = "0.00", tdStr = "0.0 MB", tuStr = "0.0 MB"
        if dt > 0 {
            if hasNetworkBaseline {
                let din = ti - previousNetIn; let dout = to - previousNetOut
                totalNetIn += din; totalNetOut += dout
                dStr = String(format: "%.2f", Double(din) / dt / 1_048_576)
                uStr = String(format: "%.2f", Double(dout) / dt / 1_048_576)
                tdStr = totalNetIn > 1_073_741_824 ? String(format: "%.2f GB", Double(totalNetIn)/1_073_741_824) : String(format: "%.1f MB", Double(totalNetIn)/1_048_576)
                tuStr = totalNetOut > 1_073_741_824 ? String(format: "%.2f GB", Double(totalNetOut)/1_073_741_824) : String(format: "%.1f MB", Double(totalNetOut)/1_048_576)
            }
            hasNetworkBaseline = true; previousNetIn = ti; previousNetOut = to; previousNetworkTime = now
        }
        return (dStr, uStr, tdStr, tuStr)
    }

    private func updateDiskSpeeds() {
        var stats = [String: UInt64]()
        let snapshot = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, snapshot, &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let props = getServiceProperties(service), let s = props["Statistics"] as? [String: Any] {
                    stats["read"] = (stats["read"] ?? 0) + (SystemMonitor.uint64(from: s["Bytes (Read)"] ?? s["BytesRead"]) ?? 0)
                    stats["write"] = (stats["write"] ?? 0) + (SystemMonitor.uint64(from: s["Bytes (Write)"] ?? s["BytesWritten"]) ?? 0)
                }
                IOObjectRelease(service); service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        let now = Date(); let dt = now.timeIntervalSince(previousTime)
        if dt > 0, let r = stats["read"], let w = stats["write"] {
            if hasDiskBaseline {
                let rs = Double(r - previousDiskRead) / dt / 1_048_576
                let ws = Double(w - previousDiskWrite) / dt / 1_048_576
                DispatchQueue.main.async { [weak self] in
                    self?.diskReadSpeed = String(format: "%.2f", rs)
                    self?.diskWriteSpeed = String(format: "%.2f", ws)
                }
            }
            hasDiskBaseline = true; previousDiskRead = r; previousDiskWrite = w; previousTime = now
        }
    }

    private func collectTemperatures() -> [TemperatureInfo] {
        var temps: [TemperatureInfo] = []
        let keys = [("TC0P", "CPU Proximity"), ("TG0D", "GPU Die"), ("Th1H", "Disk"), ("TB0T", "Battery")]
        for (k, n) in keys { if let v = SMCWrapper.shared.readKey(k), v > 0 { temps.append(TemperatureInfo(name: n, value: v)) } }
        
        // 核心温度矩阵采集 (Apple Silicon 常见键位)
        var pTemps: [TemperatureInfo] = []
        var eTemps: [TemperatureInfo] = []
        for i in 0..<16 {
            let key = String(format: "Tp%02d", i)
            if let v = SMCWrapper.shared.readKey(key), v > 0 { pTemps.append(TemperatureInfo(name: "P-Core \(i+1)", value: v)) }
        }
        for i in 0..<16 {
            let key = String(format: "Te%02d", i)
            if let v = SMCWrapper.shared.readKey(key), v > 0 { eTemps.append(TemperatureInfo(name: "E-Core \(i+1)", value: v)) }
        }
        self.tempPCoreData = pTemps
        self.tempECoreData = eTemps
        
        if temps.isEmpty { temps = [TemperatureInfo(name: "CPU (Sim)", value: 45.0)] }
        return temps
    }

    private func collectFans() -> [FanInfo] {
        var fanList: [FanInfo] = []
        for i in 0..<2 { if let v = SMCWrapper.shared.readKey("F\(i)Ac") { fanList.append(FanInfo(name: "Fan \(i+1)", rpm: v)) } }
        return fanList
    }

    private func collectBatteryStats() -> (level: Int, charging: Bool, source: String, cycles: Int, health: Int, power: Double) {
        var bLevel = 0, bCharging = false, bSource = "Unknown", bCycles = 0, bHealth = 100, bPower = 0.0
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as Array
        for s in list {
            if let d = IOPSGetPowerSourceDescription(snap, s).takeUnretainedValue() as? [String: Any] {
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maxCap = d[kIOPSMaxCapacityKey] as? Int ?? 100
                bLevel = maxCap > 0 ? (cur * 100) / maxCap : 0
                bCharging = d[kIOPSIsChargingKey] as? Bool ?? false
                bSource = d[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
            }
        }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            if let p = getServiceProperties(svc) {
                bCycles = Int(SystemMonitor.uint64(from: p["CycleCount"]) ?? 0)
                let vRaw = (p["Voltage"] as? NSNumber)?.int64Value ?? 0
                let aRaw = (p["Amperage"] as? NSNumber)?.int64Value ?? 0
                bPower = Double(abs(vRaw) * abs(aRaw)) / 1_000_000.0
                let rawMax = (p["AppleRawMaxCapacity"] as? NSNumber)?.int64Value ?? (p["MaxCapacity"] as? NSNumber)?.int64Value ?? 0
                let designCap = (p["DesignCapacity"] as? NSNumber)?.int64Value ?? (p["AppleRawDesignCapacity"] as? NSNumber)?.int64Value ?? 1
                bHealth = designCap > 0 ? Int((rawMax * 100) / designCap) : 100
                if bHealth < 5, let hp = p["BatteryHealth"] as? Int { bHealth = hp }
                else if bHealth > 100 { bHealth = 100 }
            }
            IOObjectRelease(svc)
        }
        return (bLevel, bCharging, bSource, bCycles, bHealth, bPower)
    }

    private func updateBatteryStats() {
        let b = collectBatteryStats()
        DispatchQueue.main.async { [weak self] in
            self?.batteryLevel = b.level
            self?.isCharging = b.charging
            self?.powerSource = b.source
            self?.batteryCycles = b.cycles
            self?.batteryHealth = b.health
            self?.batteryPower = b.power
        }
    }

    private func collectTopProcesses() -> (cpu: [ProcessInfoData], mem: [ProcessInfoData]) {
        let cp = parseProcessOutput(runShellCommand("ps -eo pid,pcpu,comm -r | head -n 6"), unit: "%")
        let mp = parseProcessOutput(runShellCommand("ps -eo pid,pmem,comm -m | head -n 6"), unit: "%")
        return (cp, mp)
    }

    private func collectDiskUsage() -> (usage: Double, used: String, total: String) {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let tot = attrs[.systemSize] as? NSNumber, let free = attrs[.systemFreeSize] as? NSNumber {
            let u = tot.uint64Value - free.uint64Value
            return (Double(u) / Double(tot.uint64Value) * 100, 
                    String(format: "%.1f", Double(u) / 1_073_741_824), 
                    String(format: "%.1f", Double(tot.uint64Value) / 1_073_741_824))
        }
        return (0, "N/A", "N/A")
    }

    private func collectDiskHealth() -> String {
        var pct: Int?
        for key in ["AppleANS2NVMeController", "AppleNVMeSMARTUserClient"] {
            let matching = IOServiceMatching(key); var it: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS {
                var s = IOIteratorNext(it)
                while s != 0 {
                    if let p = getServiceProperties(s), let d = p["SmartData"] as? Data, d.count > 5 { pct = Int(d[5]) }
                    IOObjectRelease(s); if pct != nil { break }; s = IOIteratorNext(it)
                }
                IOObjectRelease(it); if pct != nil { break }
            }
        }
        return pct != nil ? "\(100 - pct!)% (寿命剩余)" : "健康 (API受限)"
    }

    private func collectSecurityStatus() -> (sip: String, fw: String, fv: String) {
        let sip = runShellCommand("csrutil status").contains("enabled") ? "已开启" : "已禁用"
        let fwRaw = runShellCommand("defaults read /Library/Preferences/com.apple.alf globalstate").trimmingCharacters(in: .whitespacesAndNewlines)
        let fv = runShellCommand("fdesetup status").contains("is On") ? "已开启" : "已关闭"
        let fw = (fwRaw == "1" || fwRaw == "2") ? "已开启" : "已关闭"
        return (sip, fw, fv)
    }

    private func collectSystemUptime() -> String {
        var bt = timeval(); var sz = MemoryLayout<timeval>.size; var mib = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &bt, &sz, nil, 0) != -1 {
            let ut = Date().timeIntervalSince(Date(timeIntervalSince1970: Double(bt.tv_sec) + Double(bt.tv_usec)/1_000_000.0))
            let d = Int(ut)/86400; let h = (Int(ut)%86400)/3600; let m = (Int(ut)%3600)/60
            return d > 0 ? "\(d)d \(h)h \(m)m" : "\(h)h \(m)m"
        }
        return "N/A"
    }

    private func collectPrivacyStatus() -> Bool {
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.contains { $0.isInUseByAnotherApplication }
    }

    private func collectNetworkLatency() -> String {
        let task = Process(); task.launchPath = "/sbin/ping"; task.arguments = ["-c", "1", "-t", "1", "1.1.1.1"]
        let pipe = Pipe(); task.standardOutput = pipe
        try? task.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8), let r = out.range(of: "time="), let ms = out[r.upperBound...].range(of: " ms") {
            return "\(out[r.upperBound..<ms.lowerBound]) ms"
        }
        return "超时"
    }

    private func collectWifiStats() -> (ssid: String, rssi: Int) {
        if let iface = CWWiFiClient.shared().interface(), iface.powerOn() {
            return (iface.ssid() ?? "未连接", iface.rssiValue())
        }
        return ("未连接", 0)
    }

    private func collectGameModeStatus() -> Bool {
        if let screen = NSScreen.main {
            let hasMenuBar = screen.frame.height > screen.visibleFrame.height + 10
            if !hasMenuBar {
                if let frontApp = NSWorkspace.shared.frontmostApplication, 
                   frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                    return true
                }
            }
        }
        return false
    }

    private func collectTopNetworkProcesses() -> [ProcessInfoData] {
        let lines = runShellCommand("top -l 1 -n 10 -o IO -stats pid,command,io").components(separatedBy: .newlines)
        var procs: [ProcessInfoData] = []
        for l in lines {
            let p = l.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if p.count >= 3, let io = p.last, (io.contains("M") || io.contains("K")), let pid = Int32(p[0]) {
                let val = Double(io.replacingOccurrences(of: "M", with: "").replacingOccurrences(of: "K", with: "").replacingOccurrences(of: "B", with: "")) ?? 0
                procs.append(ProcessInfoData(pid: pid, name: p.dropFirst().dropLast().joined(separator: " "), value: val, unit: io.contains("M") ? "MB" : "KB"))
            }
        }
        return Array(procs.prefix(5))
    }

    private func updateMenuBarUI() {
        let t = temperatures.map { $0.value }.max() ?? 0
        if UserDefaults.standard.bool(forKey: "EnableMenuBarRotation"), Date().timeIntervalSince(lastMenuBarRotationTime) >= 5.0 {
            menuBarRotationIndex = (menuBarRotationIndex + 1) % 3
            lastMenuBarRotationTime = Date()
            UserDefaults.standard.set(["cpu", "mem", "net"][menuBarRotationIndex], forKey: "MenuBarDisplayType")
        }
        menuBarColor = (t > 85 || cpuUsage > 90) ? .red : (t > 70 || cpuUsage > 70 ? .orange : .primary)
    }

    private func processAlerts() {
        guard UserDefaults.standard.bool(forKey: "EnableAlerts") else { return }
        let now = Date()
        for t in temperatures where t.value > 90 { sendAlert(id: "cpu_temp", title: "温度过高", body: "\(t.name): \(t.value)°C", now: now) }
        if memoryUsage > 95 { sendAlert(id: "mem", title: "内存不足", body: "\(String(format: "%.1f", memoryUsage))%", now: now) }
    }
    
    private func sendAlert(id: String, title: String, body: String, now: Date) {
        if let last = lastAlertTime[id], now.timeIntervalSince(last) < alertCooldown { return }
        lastAlertTime[id] = now; NotificationManager.shared.sendNotification(title: title, body: body, identifier: id)
    }

    func buildDeviceSummary() -> String {
        let d = DeviceManager.shared
        return "Device: \(d.deviceName) (\(d.model))\nOS: \(d.osVersion)\nCPU: \(String(format: "%.1f", cpuUsage))%\nMem: \(usedMemory)/\(totalMemory)GB\nDisk: \(diskUsage)%\nBattery: \(batteryLevel)% (Health: \(batteryHealth)%)"
    }

    func exportHistoryToCSV() {
        var csv = "Timestamp,CPU(%),Mem(%),Disk(%),NetDown(MB/s),NetUp(MB/s),Battery(%)\n"
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for s in self.fullHistory {
            csv += "\(df.string(from: s.timestamp)),\(s.cpuUsage),\(s.memoryUsage),\(s.diskUsage),\(s.networkDownloadSpeedMBps),\(s.networkUploadSpeedMBps),\(s.batteryLevel)\n"
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "history.csv"
        panel.begin { if $0 == .OK, let url = panel.url { try? csv.write(to: url, atomically: true, encoding: .utf8) } }
    }

    private func parseProcessOutput(_ out: String, unit: String) -> [ProcessInfoData] {
        var res: [ProcessInfoData] = []
        for l in out.components(separatedBy: .newlines).dropFirst() {
            let p = l.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if p.count >= 3, let pid = Int32(p[0]), let v = Double(p[1]), v > 0.1 {
                let name = p.dropFirst(2).joined(separator: " ")
                res.append(ProcessInfoData(pid: pid, name: name.components(separatedBy: "/").last ?? name, value: v, unit: unit))
            }
        }
        return res
    }

    private func runShellCommand(_ cmd: String) -> String {
        let t = Process(); let p = Pipe(); t.standardOutput = p; t.standardError = p; t.arguments = ["-c", cmd]; t.launchPath = "/bin/sh"
        try? t.run(); let d = p.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8) ?? ""
    }

    private func getServiceProperties(_ svc: io_service_t) -> [String: Any]? {
        var p: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(svc, &p, kCFAllocatorDefault, 0) == KERN_SUCCESS { return p?.takeRetainedValue() as? [String: Any] }
        return nil
    }
    
    private static func uint64(from any: Any?) -> UInt64? {
        if let n = any as? NSNumber { return n.uint64Value }
        if let v = any as? UInt64 { return v }
        if let v = any as? Int64, v >= 0 { return UInt64(v) }
        if let v = any as? Int, v >= 0 { return UInt64(v) }
        if let v = any as? String { return UInt64(v) }
            return nil
    }

    func checkPowerSaveMode() {
        let shouldEnable = UserDefaults.standard.bool(forKey: "EnableSmartPowerSave") && 
                           powerSource == "Battery Power" && 
                           batteryLevel < 20
        if shouldEnable != isPowerSaveModeActive {
            DispatchQueue.main.async { [weak self] in
                self?.isPowerSaveModeActive = shouldEnable
                self?.restartTimer()
            }
        }
    }

    func fetchPublicIP() {
        let url = URL(string: "https://api.ipify.org?format=json")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: String], let ip = json["ip"] else { return }
            DispatchQueue.main.async { self?.publicIP = ip }
        }.resume()
    }

    func fetchAIInsight() {
        let baseURL = UserDefaults.standard.string(forKey: "AI_BaseURL") ?? "https://api.openai.com/v1"
        let apiKey = UserDefaults.standard.string(forKey: "AI_APIKey") ?? ""
        let model = UserDefaults.standard.string(forKey: "AI_ModelName") ?? "gpt-3.5-turbo"
        guard !apiKey.isEmpty else { aiInsight = "请先配置 API Key"; return }
        aiInsight = "AI 正在思考中..."
        let systemInfo = "CPU: \(cpuUsage)%, Mem: \(usedMemory)GB, Disk: \(diskUsage)%"
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": model, "messages": [["role":"system","content":"Brief advisor."],["role":"user","content":systemInfo]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let content = (choices.first?["message"] as? [String: Any])?["content"] as? String {
                DispatchQueue.main.async { self?.aiInsight = content.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }.resume()
    }
    
    func performQuickCleanup() {
        let initialUsed = Double(usedMemory) ?? 0
        monitoringQueue.async { [weak self] in
            autoreleasepool { var _: [UInt8]? = Array(repeating: 0, count: 600 * 1024 * 1024) }
            _ = self?.runShellCommand("/usr/sbin/purge")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let freed = max(0, initialUsed - (Double(self?.usedMemory ?? "0") ?? 0))
                NotificationManager.shared.sendNotification(title: "清理完成", body: "释放了 \(String(format: "%.1f", freed)) GB", identifier: "cleanup")
            }
        }
    }

    func killProcess(pid: Int32) {
        _ = try? Process.run(URL(fileURLWithPath: "/bin/kill"), arguments: ["-9", String(pid)])
        monitoringQueue.async { [weak self] in self?.updateTopProcesses() }
    }
    
    private func updateTopProcesses() {
        let tp = collectTopProcesses()
        DispatchQueue.main.async { [weak self] in
            self?.topCPUProcesses = tp.cpu
            self?.topMemoryProcesses = tp.mem
        }
    }
}

struct TemperatureInfo { let name: String; let value: Double }
struct FanInfo { let name: String; let rpm: Double }
struct ProcessInfoData: Identifiable { let id = UUID(); let pid: Int32; let name: String; let value: Double; let unit: String }
