//
//  PressureOffsetManger.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/3.
//  最後更新 2025/07/17

import SwiftUI
import Foundation
import MQTTNIO
import Combine

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
