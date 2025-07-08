//
//  BLEParser.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/13.
//  最後更新 2025/07/08
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
    var devices: [DeviceInfo]         // 5個裝置資訊
    let hasReachedTarget: Bool        // 是否有裝置達到100次
}

// 裝置資訊結構
struct DeviceInfo: Codable, Equatable, Identifiable {
    var id: String { "\(deviceId)-\(timestamp.timeIntervalSince1970)" }
    
    let timestamp: Date  // Timestamp
    let deviceId: String   // 裝置ID
    let count: UInt8       // 接收次數
    let receptionRate: Double // 接收率（次/秒）
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
            
            guard deviceIdByte != 0 else {
                continue
            }
            
            let count = dataBytes[baseIndex + 1]
            
            // 檢查是否達到100次
            if count >= 100 {
                hasReachedTarget = true
            }
            
            let deviceIdInt = Int(deviceIdByte)
            let deviceIdString = String(deviceIdInt)
            // 計算接收率 (次/秒)
            let receptionRate = seconds > 0 ? Double(count) / Double(seconds) : 0.0
            
            let deviceInfo = DeviceInfo(
                timestamp: Date(),
                deviceId: deviceIdString,
                count: count,
                receptionRate: receptionRate
            )
            devices.append(deviceInfo)
        }
        
        devices.sort { $0.count > $1.count }
        
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
