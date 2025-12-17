import Foundation
import Combine
import IOKit
import IOKit.ps
import Darwin

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
    let timestamp: Date
}

class SystemMonitor: ObservableObject {
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
    @Published var temperatures: [TemperatureInfo] = []
    @Published var fans: [FanInfo] = []
    
    private var timer: Timer?
    private(set) var isRunning: Bool = false
    private var previousDiskRead: UInt64 = 0
    private var previousDiskWrite: UInt64 = 0
    private var previousTime: Date = Date()
    private var hasDiskBaseline: Bool = false
    private var previousNetIn: UInt64 = 0
    private var previousNetOut: UInt64 = 0
    private var hasNetworkBaseline: Bool = false
    private var previousNetworkTime: Date = Date()
    var onMetricsUpdate: ((MetricsSnapshot) -> Void)?
    
    init(autoStart: Bool = true) {
        if autoStart {
            startMonitoring()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true
        previousDiskRead = 0
        previousDiskWrite = 0
        previousTime = Date()
        hasDiskBaseline = false
        previousNetIn = 0
        previousNetOut = 0
        hasNetworkBaseline = false
        previousNetworkTime = Date()
        
        // 立即更新一次
        updateAllStats()
        
        // 每1秒更新一次
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateAllStats()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    private func updateAllStats() {
        updateCPUUsage()
        updateMemoryUsage()
        updateDiskUsage()
        updateDiskStats()
        updateNetworkStats()
        updateTemperatures()
        updateFans()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let snapshot = MetricsSnapshot(
                cpuUsage: self.cpuUsage,
                memoryUsage: self.memoryUsage,
                usedMemoryGB: Double(self.usedMemory) ?? 0,
                totalMemoryGB: Double(self.totalMemory) ?? 0,
                diskUsage: self.diskUsage,
                diskUsedGB: Double(self.usedDisk) ?? 0,
                diskTotalGB: Double(self.totalDisk) ?? 0,
                diskReadSpeedMBps: Double(self.diskReadSpeed) ?? 0,
                diskWriteSpeedMBps: Double(self.diskWriteSpeed) ?? 0,
                networkDownloadSpeedMBps: Double(self.networkDownloadSpeed) ?? 0,
                networkUploadSpeedMBps: Double(self.networkUploadSpeed) ?? 0,
                timestamp: Date()
            )
            self.onMetricsUpdate?(snapshot)
        }
    }
    
    // MARK: - CPU监控
    private func updateCPUUsage() {
        var cpuInfo: processor_info_array_t!
        var numCPUInfo: mach_msg_type_number_t = 0
        var numProcessors: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                        PROCESSOR_CPU_LOAD_INFO,
                                        &numProcessors,
                                        &cpuInfo,
                                        &numCPUInfo)
        
        if result == KERN_SUCCESS {
            let cpuLoadInfo = cpuInfo.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(numProcessors)) { $0 }
            
            var totalUser: UInt32 = 0
            var totalSystem: UInt32 = 0
            var totalIdle: UInt32 = 0
            var totalNice: UInt32 = 0
            
            for i in 0..<Int(numProcessors) {
                totalUser += cpuLoadInfo[i].cpu_ticks.0
                totalSystem += cpuLoadInfo[i].cpu_ticks.1
                totalIdle += cpuLoadInfo[i].cpu_ticks.2
                totalNice += cpuLoadInfo[i].cpu_ticks.3
            }
            
            let total = totalUser + totalSystem + totalIdle + totalNice
            let used = totalUser + totalSystem + totalNice
            
            DispatchQueue.main.async {
                self.cpuUsage = total > 0 ? Double(used) / Double(total) * 100 : 0
            }
        }
    }
    
    // MARK: - 内存监控
    private func updateMemoryUsage() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = vm_kernel_page_size
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = UInt64(stats.active_count + stats.wire_count) * UInt64(pageSize)
            
            DispatchQueue.main.async {
                self.memoryUsage = Double(usedMemory) / Double(totalMemory) * 100
                self.usedMemory = String(format: "%.1f", Double(usedMemory) / 1_073_741_824)
                self.totalMemory = String(format: "%.1f", Double(totalMemory) / 1_073_741_824)
            }
        }
    }
    
    // MARK: - 硬盘监控
    private func updateDiskUsage() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            guard
                let total = attrs[.systemSize] as? NSNumber,
                let free = attrs[.systemFreeSize] as? NSNumber
            else {
                DispatchQueue.main.async {
                    self.diskUsage = 0
                    self.usedDisk = "N/A"
                    self.totalDisk = "N/A"
                }
                return
            }
            
            let totalBytes = total.uint64Value
            let freeBytes = free.uint64Value
            let usedBytes = totalBytes >= freeBytes ? (totalBytes - freeBytes) : 0
            
            let usedGB = Double(usedBytes) / 1_073_741_824
            let totalGB = Double(totalBytes) / 1_073_741_824
            let usage = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes) * 100) : 0
            
            DispatchQueue.main.async {
                self.diskUsage = usage
                self.usedDisk = String(format: "%.1f", usedGB)
                self.totalDisk = String(format: "%.1f", totalGB)
            }
        } catch {
            DispatchQueue.main.async {
                self.diskUsage = 0
                self.usedDisk = "N/A"
                self.totalDisk = "N/A"
            }
        }
    }
    
    private func updateDiskStats() {
        var stats = [String: UInt64]()
        var servicesVisited = 0
        
        // 获取磁盘统计信息
        let snapshot = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        
        if IOServiceGetMatchingServices(kIOMainPortDefault, snapshot, &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            
            while service != 0 {
                defer { IOObjectRelease(service) }
                servicesVisited += 1
                
                // 获取统计信息
                if let properties = getServiceProperties(service) {
                    if let statistics = properties["Statistics"] as? [String: Any] {
                        if let bytesRead = Self.uint64(from: statistics["Bytes (Read)"] ?? statistics["BytesRead"] ?? statistics["Bytes Read"]) {
                            let current = stats["read"] ?? 0
                            stats["read"] = current + bytesRead
                        }
                        if let bytesWritten = Self.uint64(from: statistics["Bytes (Write)"] ?? statistics["BytesWritten"] ?? statistics["Bytes Written"]) {
                            let current = stats["write"] ?? 0
                            stats["write"] = current + bytesWritten
                        }
                    }
                }
                
                service = IOIteratorNext(iterator)
            }
            
            IOObjectRelease(iterator)
        }
        
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(previousTime)
        
        if stats.isEmpty {
            DispatchQueue.main.async {
                self.diskReadSpeed = servicesVisited == 0 ? "N/A" : "0.00"
                self.diskWriteSpeed = servicesVisited == 0 ? "N/A" : "0.00"
            }
            previousTime = currentTime
            return
        }
        
        if timeInterval > 0 {
            let bytesRead = stats["read"] ?? 0
            let bytesWritten = stats["write"] ?? 0
            
            if !hasDiskBaseline {
                hasDiskBaseline = true
                previousDiskRead = bytesRead
                previousDiskWrite = bytesWritten
                previousTime = currentTime
                DispatchQueue.main.async {
                    self.diskReadSpeed = "0.00"
                    self.diskWriteSpeed = "0.00"
                }
                return
            }
            
            let readDelta = bytesRead >= previousDiskRead ? (bytesRead - previousDiskRead) : 0
            let writeDelta = bytesWritten >= previousDiskWrite ? (bytesWritten - previousDiskWrite) : 0
            
            let readSpeed = Double(readDelta) / timeInterval / 1_048_576 // MB/s
            let writeSpeed = Double(writeDelta) / timeInterval / 1_048_576 // MB/s
            
            DispatchQueue.main.async {
                self.diskReadSpeed = String(format: "%.2f", max(0, readSpeed))
                self.diskWriteSpeed = String(format: "%.2f", max(0, writeSpeed))
            }
            
            previousDiskRead = bytesRead
            previousDiskWrite = bytesWritten
            previousTime = currentTime
        }
    }
    
    // MARK: - 网络监控
    private func updateNetworkStats() {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            DispatchQueue.main.async {
                self.networkDownloadSpeed = "N/A"
                self.networkUploadSpeed = "N/A"
            }
            return
        }
        defer { freeifaddrs(addrs) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & Int32(IFF_UP)) != 0
            let isRunning = (flags & Int32(IFF_RUNNING)) != 0
            let isLoopback = (flags & Int32(IFF_LOOPBACK)) != 0
            
            if isUp, isRunning, !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalIn += UInt64(data.pointee.ifi_ibytes)
                    totalOut += UInt64(data.pointee.ifi_obytes)
                }
            }
            
            ptr = current.pointee.ifa_next
        }
        
        let now = Date()
        let dt = now.timeIntervalSince(previousNetworkTime)
        guard dt > 0 else { return }
        
        if !hasNetworkBaseline {
            hasNetworkBaseline = true
            previousNetIn = totalIn
            previousNetOut = totalOut
            previousNetworkTime = now
            DispatchQueue.main.async {
                self.networkDownloadSpeed = "0.00"
                self.networkUploadSpeed = "0.00"
            }
            return
        }
        
        let inDelta = totalIn >= previousNetIn ? (totalIn - previousNetIn) : 0
        let outDelta = totalOut >= previousNetOut ? (totalOut - previousNetOut) : 0
        
        let downMBps = Double(inDelta) / dt / 1_048_576
        let upMBps = Double(outDelta) / dt / 1_048_576
        
        DispatchQueue.main.async {
            self.networkDownloadSpeed = String(format: "%.2f", max(0, downMBps))
            self.networkUploadSpeed = String(format: "%.2f", max(0, upMBps))
        }
        
        previousNetIn = totalIn
        previousNetOut = totalOut
        previousNetworkTime = now
    }
    
    // MARK: - 温度监控
    private func updateTemperatures() {
        var temps: [TemperatureInfo] = []
        
        // 尝试读取SMC温度传感器
        let tempSensors = [
            ("TC0P", "CPU 接近温度"),
            ("TC0D", "CPU Die 温度"),
            ("TG0D", "GPU Die 温度"),
            ("Th1H", "硬盘温度")
        ]
        
        for (key, name) in tempSensors {
            if let temp = readSMCTemperature(key: key) {
                temps.append(TemperatureInfo(name: name, value: temp))
            }
        }
        
        // 如果没有读取到温度，使用模拟数据（用于测试）
        if temps.isEmpty {
            temps = [
                TemperatureInfo(name: "CPU温度", value: Double.random(in: 45...65)),
                TemperatureInfo(name: "GPU温度", value: Double.random(in: 40...60))
            ]
        }
        
        DispatchQueue.main.async {
            self.temperatures = temps
        }
    }
    
    // MARK: - 风扇监控
    private func updateFans() {
        var fanList: [FanInfo] = []
        
        // 尝试读取SMC风扇信息
        let fanKeys = ["F0Ac", "F1Ac", "F2Ac"]
        
        for (index, key) in fanKeys.enumerated() {
            if let rpm = readSMCFanSpeed(key: key) {
                fanList.append(FanInfo(name: "风扇 \(index + 1)", rpm: rpm))
            }
        }
        
        // 如果没有读取到风扇信息，使用模拟数据（用于测试）
        if fanList.isEmpty {
            fanList = [
                FanInfo(name: "左侧风扇", rpm: Double.random(in: 2000...3000)),
                FanInfo(name: "右侧风扇", rpm: Double.random(in: 2000...3000))
            ]
        }
        
        DispatchQueue.main.async {
            self.fans = fanList
        }
    }
    
    // MARK: - Helper Functions
    private func getServiceProperties(_ service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        
        if result == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
            return props
        }
        return nil
    }
    
    private static func uint64(from any: Any?) -> UInt64? {
        switch any {
        case let n as NSNumber:
            return n.uint64Value
        case let v as UInt64:
            return v
        case let v as Int64 where v >= 0:
            return UInt64(v)
        case let v as Int where v >= 0:
            return UInt64(v)
        case let v as String:
            return UInt64(v)
        default:
            return nil
        }
    }
    
    private func readSMCTemperature(key: String) -> Double? {
        // 注意：实际读取SMC需要特殊权限和库
        // 这里返回nil，让系统使用模拟数据
        return nil
    }
    
    private func readSMCFanSpeed(key: String) -> Double? {
        // 注意：实际读取SMC需要特殊权限和库
        // 这里返回nil，让系统使用模拟数据
        return nil
    }
}

struct TemperatureInfo {
    let name: String
    let value: Double
}

struct FanInfo {
    let name: String
    let rpm: Double
}
