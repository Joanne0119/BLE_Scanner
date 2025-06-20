//
//  BLEParser.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/13.
//  最後更新 2025/06/20
//
import SwiftUI
import Foundation
import MQTTNIO
import Combine

// 解析後的數據結構
struct ParsedBLEData: Codable, Equatable {
    let temperature: Int             // 1 byte 溫度
    let atmosphericPressure: Double  // 3 bytes 大氣壓力
    let seconds: UInt8                // 1 byte 秒數
    let devices: [DeviceInfo]         // 5個裝置資訊
    let hasReachedTarget: Bool        // 是否有裝置達到100次
}

// 裝置資訊結構
struct DeviceInfo: Codable, Equatable {
    let deviceId: String   // 裝置ID
    let count: UInt8       // 接收次數
    let receptionRate: Double // 接收率（次/秒）
}

struct PressureOffset: Codable, Identifiable {
    let id = UUID()
    let deviceId: String
    let offset: Double
    let baseAltitude: Double
    let timestamp: Date
    
    init(deviceId: String, offset: Double, baseAltitude: Double) {
        self.deviceId = deviceId
        self.offset = offset
        self.baseAltitude = baseAltitude
        self.timestamp = Date()
    }
    
    init(deviceId: String, offset: Double, baseAltitude: Double, timestamp: Date) {
       self.deviceId = deviceId
       self.offset = offset
       self.baseAltitude = baseAltitude
       self.timestamp = timestamp
   }
}

class BLEDataParser {
    
    // 解析數據字串
    func parseDataString(_ dataStr: String) -> ParsedBLEData? {
        guard let dataBytes = parseHexInput(dataStr) else {
            print("無法解析 hex 字串: \(dataStr)")
            return nil
        }
        
        // 檢查數據長度是否正確 (1 + 3 + 1 + 10 = 14 bytes)
        guard dataBytes.count == 15 else {
            print("數據長度錯誤，期望15 bytes，實際: \(dataBytes.count)")
            return nil
        }
        
        return parseDataBytes(dataBytes)
    }
    
    // 解析位元組數據
    func parseDataBytes(_ dataBytes: [UInt8]) -> ParsedBLEData? {
        guard dataBytes.count == 15 else {
            return nil
        }
        
        //溫度（第1 byte)
        let temperature = Int(dataBytes[0])
        
        // 解析大氣壓力 (前2到4bytes)
        let pressureBytes = Array(dataBytes[1..<4])
        let atmosphericPressure = calculateAtmosphericPressure(pressureBytes)
        
        // 解析秒數 (第5byte)
        let seconds = dataBytes[4]
        
        // 解析5個裝置資訊 (後10 bytes)
        var devices: [DeviceInfo] = []
        var hasReachedTarget = false
        
        for i in 0..<5 {
            let baseIndex = 5 + (i * 2)  // 從第5個byte開始，每個裝置佔2 bytes
            let deviceIdByte = dataBytes[baseIndex]
            let count = dataBytes[baseIndex + 1]
            
            // 檢查是否達到100次 (0x64 = 100)
            if count >= 100 {
                hasReachedTarget = true
            }
            
            let deviceIdString = String(format: "%02X", deviceIdByte)
            // 計算接收率 (次/秒)
            let receptionRate = seconds > 0 ? Double(count) / Double(seconds) : 0.0
            
            let deviceInfo = DeviceInfo(
                deviceId: deviceIdString,
                count: count,
                receptionRate: receptionRate
            )
            devices.append(deviceInfo)
        }
        
        return ParsedBLEData(
            temperature: temperature,
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
        result += "溫度: \(parsedData.temperature) °C\n"
        result += "大氣壓力: \(String(format: "%.2f", parsedData.atmosphericPressure)) hPa\n"
        result += "時間: \(parsedData.seconds) 秒\n"
        result += "裝置資訊:\n"
        
        for (index, device) in parsedData.devices.enumerated() {
            result += "  裝置\(index + 1) - ID: \(device.deviceId), "
            result += "次數: \(device.count), "
            result += "接收率: \(String(format: "%.2f", device.receptionRate)) 次/秒\n"
        }
        
        result += "是否達到目標(100次): \(parsedData.hasReachedTarget ? "是" : "否")\n"
        
        return result
    }
}


class PressureOffsetManager: ObservableObject {
    @Published var offsets: [String: PressureOffset] = [:]
    @Published var mqttStatus: String = "未連接"
        
    private var mqttManager: MQTTManager
    private var cancellables = Set<AnyCancellable>()
    
    init(mqttManager: MQTTManager) {
       self.mqttManager = mqttManager
       setupMQTTCallbacks()
       setupMQTTStatusBinding()
   }
    
    private func setupMQTTCallbacks() {
        // 當收到偏差值更新時
        mqttManager.onOffsetReceived = { [weak self] pressureOffset in
            self?.updateOffsetFromMQTT(pressureOffset)
        }
        
        // 當收到偏差值刪除時
        mqttManager.onOffsetDeleted = { [weak self] deviceId in
            self?.deleteOffsetFromMQTT(deviceId)
        }
    }
    
    private func setupMQTTStatusBinding() {
        mqttManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.mqttStatus, on: self)
            .store(in: &cancellables)
    }
    
    func connectMQTT() {
        mqttManager.connect()
    }
    
    func disconnectMQTT() {
        mqttManager.disconnect()
    }
    
    func requestAllOffsetsFromServer() {
        mqttManager.requestAllOffsets()
    }
    
    
    func setOffset(for deviceId: String, offset: Double, baseAltitude: Double) {
        let pressureOffset = PressureOffset(deviceId: deviceId, offset: offset, baseAltitude: baseAltitude)
        offsets[deviceId] = pressureOffset
        saveOffsets()
        
        // 同步到 MQTT
        mqttManager.publishOffset(pressureOffset)
    }
    
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
        
        // 同步刪除到 MQTT
        mqttManager.deleteOffset(deviceId: deviceId)
    }
    
    func clearAllOffsets() {
        // 先發送所有刪除訊息
        for deviceId in offsets.keys {
            mqttManager.deleteOffset(deviceId: deviceId)
        }
        
        offsets.removeAll()
        saveOffsets()
    }
    
    private func updateOffsetFromMQTT(_ pressureOffset: PressureOffset) {
        // 檢查是否需要更新（避免循環更新）
        if let existingOffset = offsets[pressureOffset.deviceId] {
            // 比較時間戳，只更新較新的資料
            if pressureOffset.timestamp > existingOffset.timestamp {
                offsets[pressureOffset.deviceId] = pressureOffset
                saveOffsets()
            }
        } else {
            // 新的裝置偏差值
            offsets[pressureOffset.deviceId] = pressureOffset
            saveOffsets()
        }
    }
    
    private func deleteOffsetFromMQTT(_ deviceId: String) {
        offsets.removeValue(forKey: deviceId)
        saveOffsets()
    }
    
    // 保存到本地
    private func saveOffsets() {
        if let encoded = try? JSONEncoder().encode(Array(offsets.values)) {
            UserDefaults.standard.set(encoded, forKey: "PressureOffsets")
        }
    }
    
    func loadOffsets() {
        // 從本地加载
        if let data = UserDefaults.standard.data(forKey: "PressureOffsets"),
           let decoded = try? JSONDecoder().decode([PressureOffset].self, from: data) {
            offsets = Dictionary(uniqueKeysWithValues: decoded.map { ($0.deviceId, $0) })
        }
        // 載入後連接 MQTT 並請求最新資料
        connectMQTT()
        
        // 延遲一下再請求，確保連接已建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.requestAllOffsetsFromServer()
        }
    }
    
    func loadAndSyncOffsets() {
        // 1. 從本地加載
        if let data = UserDefaults.standard.data(forKey: "PressureOffsets"),
           let decoded = try? JSONDecoder().decode([PressureOffset].self, from: data) {
            offsets = Dictionary(uniqueKeysWithValues: decoded.map { ($0.deviceId, $0) })
        }
        
        // 2. 連接 MQTT
        connectMQTT()
        
        // 3. 連接後從伺服器請求最新資料
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.requestAllOffsetsFromServer()
        }
    }
    
    
    func getCalibrationInfo(for deviceId: String) -> String {
        guard let offset = offsets[deviceId] else {
            return "未校正"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeString = formatter.string(from: offset.timestamp)
        
        return "海拔: \(String(format: "%.1f", offset.baseAltitude))m\n偏差: \(String(format: "%.2f", offset.offset))hPa\n時間: \(timeString)"
    }
    
    func exportOffsetsAsJSON() -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(offsets.values))
            return String(data: data, encoding: .utf8)
        } catch {
            print("匯出 JSON 失敗: \(error)")
            return nil
        }
    }
    
    func importOffsetsFromJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        
        do {
            let importedOffsets = try JSONDecoder().decode([PressureOffset].self, from: data)
            
            // 合併匯入的資料
            for offset in importedOffsets {
                offsets[offset.deviceId] = offset
                // 同步到 MQTT
                mqttManager.publishOffset(offset)
            }
            
            saveOffsets()
            return true
        } catch {
            print("匯入 JSON 失敗: \(error)")
            return false
        }
    }
    
}
