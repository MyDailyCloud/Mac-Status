import Foundation
import IOKit

/// 简单的 SMC (System Management Controller) 包装器，用于读取硬件传感器数据
class SMCWrapper {
    static let shared = SMCWrapper()
    
    private var connection: io_connect_t = 0
    private var opened = false
    
    // SMC 结构体定义
    private struct SMCKeyData_t {
        var key: UInt32 = 0
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
    
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    
    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
    
    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private init() {
        open()
    }
    
    deinit {
        close()
    }
    
    func open() {
        guard !opened else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            return
        }
        
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        
        if result == kIOReturnSuccess {
            opened = true
        }
    }
    
    func close() {
        if opened {
            IOServiceClose(connection)
            opened = false
        }
    }
    
    /// 将 4 字符 Key 转换为 UInt32
    private func stringToUInt32(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for char in s.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
    
    /// 获取 Key 信息
    private func getKeyInfo(_ key: UInt32) -> SMCKeyInfoData? {
        var inputStruct = SMCKeyData()
        inputStruct.key = key
        inputStruct.data8 = 9 // kSMCGetKeyInfo
        
        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size
        
        let result = IOConnectCallMethod(connection, 2, nil, 0, &inputStruct, MemoryLayout<SMCKeyData>.size, nil, nil, &outputStruct, &outputSize)
        
        if result == kIOReturnSuccess {
            return outputStruct.keyInfo
        }
        return nil
    }
    
    /// 读取 SMC 数据
    func readKey(_ keyString: String) -> Double? {
        guard opened else { return nil }
        
        let key = stringToUInt32(keyString)
        guard let info = getKeyInfo(key) else { return nil }
        
        var inputStruct = SMCKeyData()
        inputStruct.key = key
        inputStruct.keyInfo.dataSize = info.dataSize
        inputStruct.data8 = 5 // kSMCReadKey
        
        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size
        
        let result = IOConnectCallMethod(connection, 2, nil, 0, &inputStruct, MemoryLayout<SMCKeyData>.size, nil, nil, &outputStruct, &outputSize)
        
        if result != kIOReturnSuccess {
            return nil
        }
        
        // 解析数据类型 (UInt32 4字节转 String)
        let dataType: String
        let v = outputStruct.keyInfo.dataType.bigEndian
        let bytes = [
            UInt8((v >> 24) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF)
        ]
        dataType = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""

        if dataType == "sp78" {
            // 符号位 + 7位整数 + 8位分数
            let raw = UInt16(outputStruct.bytes.0) << 8 | UInt16(outputStruct.bytes.1)
            return Double(raw) / 256.0
        } else if dataType == "fpe2" {
            // 风扇转速类型
            let raw = UInt16(outputStruct.bytes.0) << 8 | UInt16(outputStruct.bytes.1)
            return Double(raw) / 4.0
        } else if dataType == "flt " {
            // 32位浮点数
            var val: Float = 0
            withUnsafeMutablePointer(to: &val) { ptr in
                let bytes = [outputStruct.bytes.0, outputStruct.bytes.1, outputStruct.bytes.2, outputStruct.bytes.3]
                ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { dest in
                    for i in 0..<4 { dest[i] = bytes[i] }
                }
            }
            return Double(val)
        }
        
        return nil
    }
}

