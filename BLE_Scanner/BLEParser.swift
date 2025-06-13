//
//  BLEParser.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/13.
//  最後更新 2025/06/14
//
import SwiftUI
import Foundation


// 解析後的數據結構
struct ParsedBLEData: Codable, Equatable {
    let atmosphericPressure: Double  // 3 bytes 大氣壓力
    let seconds: UInt8                // 1 byte 秒數
    let devices: [DeviceInfo]         // 5個裝置資訊
    let hasReachedTarget: Bool        // 是否有裝置達到100次
}

// 裝置資訊結構
struct DeviceInfo: Codable, Equatable {
    let deviceId: UInt8    // 裝置ID
    let count: UInt8       // 接收次數
    let receptionRate: Double // 接收率（次/秒）
}

struct PressureOffset: Codable, Identifiable {
    let id = UUID()
    let deviceId: String
    let offset: Double
    let baseAltitude: Double
    let calibrationTime: Date
    
    init(deviceId: String, offset: Double, baseAltitude: Double) {
        self.deviceId = deviceId
        self.offset = offset
        self.baseAltitude = baseAltitude
        self.calibrationTime = Date()
    }
}

class BLEDataParser {
    
    // 解析數據字串
    func parseDataString(_ dataStr: String) -> ParsedBLEData? {
        guard let dataBytes = parseHexInput(dataStr) else {
            print("無法解析 hex 字串: \(dataStr)")
            return nil
        }
        
        // 檢查數據長度是否正確 (3 + 1 + 10 = 14 bytes)
        guard dataBytes.count == 14 else {
            print("數據長度錯誤，期望14 bytes，實際: \(dataBytes.count)")
            return nil
        }
        
        return parseDataBytes(dataBytes)
    }
    
    // 解析位元組數據
    func parseDataBytes(_ dataBytes: [UInt8]) -> ParsedBLEData? {
        guard dataBytes.count == 14 else {
            return nil
        }
        
        // 解析大氣壓力 (前3 bytes)
        let pressureBytes = Array(dataBytes[0..<3])
        let atmosphericPressure = calculateAtmosphericPressure(pressureBytes)
        
        // 解析秒數 (第4 byte)
        let seconds = dataBytes[3]
        
        // 解析5個裝置資訊 (後10 bytes)
        var devices: [DeviceInfo] = []
        var hasReachedTarget = false
        
        for i in 0..<5 {
            let baseIndex = 4 + (i * 2)  // 從第5個byte開始，每個裝置佔2 bytes
            let deviceId = dataBytes[baseIndex]
            let count = dataBytes[baseIndex + 1]
            
            // 檢查是否達到100次 (0x64 = 100)
            if count >= 100 {
                hasReachedTarget = true
            }
            
            // 計算接收率 (次/秒)
            let receptionRate = seconds > 0 ? Double(count) / Double(seconds) : 0.0
            
            let deviceInfo = DeviceInfo(
                deviceId: deviceId,
                count: count,
                receptionRate: receptionRate
            )
            devices.append(deviceInfo)
        }
        
        return ParsedBLEData(
            atmosphericPressure: atmosphericPressure,
            seconds: seconds,
            devices: devices,
            hasReachedTarget: hasReachedTarget
        )
    }
    //大氣壓力計算
    private func calculateAtmosphericPressure(_ bytes: [UInt8]) -> Double {
        let value = (UInt32(bytes[0]) << 16) + (UInt32(bytes[1]) << 8) + UInt32(bytes[2])
        return Double(value) * 0.01
    }
    
    // 輔助函式：將hex字串轉換為bytes
    private func parseHexInput(_ hexString: String) -> [UInt8]? {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: cleanHex.count, by: 2) {
            let startIndex = cleanHex.index(cleanHex.startIndex, offsetBy: i)
            let endIndex = cleanHex.index(startIndex, offsetBy: 2)
            let hexByte = String(cleanHex[startIndex..<endIndex])
            
            if let byte = UInt8(hexByte, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
        }
        return bytes
    }
    
    // 格式化輸出解析結果
    func formatParseResult(_ parsedData: ParsedBLEData) -> String {
        var result = "=== BLE 數據解析結果 ===\n"
        result += "大氣壓力: \(String(format: "%.2f", parsedData.atmosphericPressure)) hPa\n"
        result += "時間: \(parsedData.seconds) 秒\n"
        result += "裝置資訊:\n"
        
        for (index, device) in parsedData.devices.enumerated() {
            result += "  裝置\(index + 1) - ID: \(String(format: "%02X", device.deviceId)), "
            result += "次數: \(device.count), "
            result += "接收率: \(String(format: "%.2f", device.receptionRate)) 次/秒\n"
        }
        
        result += "是否達到目標(100次): \(parsedData.hasReachedTarget ? "是" : "否")\n"
        
        return result
    }
}


class PressureOffsetManager: ObservableObject {
    @Published var offsets: [String: PressureOffset] = [:]
    
    // 添加或更新偏差值
    func setOffset(for deviceId: String, offset: Double, baseAltitude: Double) {
        let pressureOffset = PressureOffset(deviceId: deviceId, offset: offset, baseAltitude: baseAltitude)
        offsets[deviceId] = pressureOffset
        saveOffsets()
    }
    
    // 獲取偏差值
    func getOffset(for deviceId: String) -> Double {
        return offsets[deviceId]?.offset ?? 0.0
    }
    
    // 檢查
    func isCalibrated(deviceId: String) -> Bool {
        return offsets[deviceId] != nil
    }
    
    // 清除特定偏差值
    func clearOffset(for deviceId: String) {
        offsets.removeValue(forKey: deviceId)
        saveOffsets()
    }
    
    // 清除所有偏差值
    func clearAllOffsets() {
        offsets.removeAll()
        saveOffsets()
    }
    
    // 保存到本地
    private func saveOffsets() {
        if let encoded = try? JSONEncoder().encode(Array(offsets.values)) {
            UserDefaults.standard.set(encoded, forKey: "PressureOffsets")
        }
    }
    
    // 從本地加载
    func loadOffsets() {
        if let data = UserDefaults.standard.data(forKey: "PressureOffsets"),
           let decoded = try? JSONDecoder().decode([PressureOffset].self, from: data) {
            offsets = Dictionary(uniqueKeysWithValues: decoded.map { ($0.deviceId, $0) })
        }
    }
    
    
}
