//
//  StorageManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//  最後更新 2025/07/17

import Foundation
import SwiftUI
import Combine

struct StorageManager {
    static let storageKey = "savedPackets"

    static func save(packets: [BLEPacket]) {
        if let encoded = try? JSONEncoder().encode(packets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            // 使用 NotificationCenter 通知 UI 更新
            NotificationCenter.default.post(name: .packetsUpdated, object: nil)
        }
    }

    static func load() -> [BLEPacket] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BLEPacket].self, from: data) else {
            return []
        }
        return decoded
    }
}

// SavedPacketsStore 同步中心
class SavedPacketsStore: ObservableObject {
    @Published var packets: [BLEPacket] = []
    
    private var mqttManager: MQTTManager
    private var cancellables = Set<AnyCancellable>()

    // (初始化和 MQTT 回調設定維持不變)
    init(mqttManager: MQTTManager) {
        self.mqttManager = mqttManager
        self.packets = StorageManager.load()
        setupMQTTCallbacks()
        requestAllLogsFromServer()
    }
    
    func updateOrAppendDeviceHistory(for incomingPacket: BLEPacket) {
        guard let incomingParsedData = incomingPacket.parsedData else { return }

        // 尋找本地儲存中是否已存在相同 deviceID 的封包
        if let existingIndex = self.packets.firstIndex(where: { $0.deviceID == incomingPacket.deviceID }) {
            // 如果存在，則進行合併更新
            var existingPacket = self.packets[existingIndex]
            
            existingPacket.rawData = incomingPacket.rawData
            existingPacket.mask = incomingPacket.mask
            existingPacket.data = incomingPacket.data
            
            // 取得舊的歷史裝置資訊
            let oldDevices = existingPacket.parsedData?.devices ?? []
            let newDevices = incomingParsedData.devices
            
            // 合併新舊裝置資訊
            let combinedDevices = oldDevices + newDevices
            
            //【修改建議】更安全地更新 ParsedBLEData
            if var existingParsedData = existingPacket.parsedData {
                // 更新裝置列表
                existingParsedData.devices = combinedDevices
                // 同時更新為最新的秒數、溫度等資訊
                existingParsedData.seconds = incomingParsedData.seconds
                existingParsedData.temperature = incomingParsedData.temperature
                existingParsedData.atmosphericPressure = incomingParsedData.atmosphericPressure
                existingParsedData.hasReachedTarget = incomingParsedData.hasReachedTarget
                
                // 將修改後的 parsedData 賦值回 packet
                existingPacket.parsedData = existingParsedData
            } else {
                // 如果舊的沒有 parsedData，就直接用新的
                existingPacket.parsedData = incomingParsedData
            }
            
            // 更新其他最即時的資訊，例如 RSSI 和時間戳
            existingPacket.rssi = incomingPacket.rssi
            existingPacket.timestamp = incomingPacket.timestamp
            existingPacket.hasLostSignal = incomingPacket.hasLostSignal
            
            // 將完整更新後的封包存回陣列
            self.packets[existingIndex] = existingPacket
            
            print("已合併並更新 deviceID: \(existingPacket.deviceID) 的歷史紀錄。")
            
            // 發布到 MQTT 的應該是完整更新後的封包
            mqttManager.publishLog(existingPacket)

        } else {
            // 如果不存在，直接新增
            self.packets.append(incomingPacket)
            print("封包為首次儲存，已加入: \(incomingPacket.deviceID)")
            mqttManager.publishLog(incomingPacket)
        }
        
        // 儲存到本地
        StorageManager.save(packets: self.packets)
    }
    
    func updateOrAppend(contentsOf newPackets: [BLEPacket]) {
        // 遍歷所有從掃描器傳來的新封包
        for newPacket in newPackets {
            // 嘗試尋找本地儲存中是否已存在相同 id 的封包
            if let existingIndex = self.packets.firstIndex(where: { $0.deviceID == newPacket.deviceID }) {
                // 如果找到了，就用新的封包資料【更新】掉舊的資料
                self.packets[existingIndex] = newPacket
            } else {
                // 如果沒找到，就將這個新封包【新增】到陣列中
                self.packets.append(newPacket)
            }
        }
        
        // --- 同步與儲存 ---
        // 迴圈處理完畢後，儲存所有變動到本地
        StorageManager.save(packets: self.packets)
        
        // 將每一筆「新」的或「被更新」的日誌發布到 MQTT
        for packet in newPackets {
            mqttManager.publishLog(packet)
        }
    }

    private func setupMQTTCallbacks() {
        mqttManager.onLogReceived = { [weak self] packet in
            self?.updateLogFromMQTT(packet)
        }
        
        mqttManager.onLogDeleted = { [weak self] packetId in
            guard let uuid = UUID(uuidString: packetId) else { return }
            self?.deleteLogFromMQTT(id: uuid)
        }
    }
    
    func requestAllLogsFromServer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard self?.mqttManager.isConnected == true else { return }
            self?.mqttManager.requestAllLogs()
            print("已發送請求以同步所有伺服器日誌。")
        }
    }

    private func updateLogFromMQTT(_ packet: BLEPacket) {
        DispatchQueue.main.async {
            if let index = self.packets.firstIndex(where: { $0.id == packet.id }) {
                if packet.timestamp > self.packets[index].timestamp {
                    self.packets[index] = packet
                }
            } else {
                self.packets.append(packet)
            }
            StorageManager.save(packets: self.packets)
        }
    }

    private func deleteLogFromMQTT(id: UUID) {
        DispatchQueue.main.async {
            self.packets.removeAll(where: { $0.identifier == id.uuidString })
            StorageManager.save(packets: self.packets)
        }
    }
    
    // MARK: - 本地操作 (已整合 MQTT)
    
    /// 新增掃描結果（同時會發布到 MQTT）
    func append(_ newPackets: [BLEPacket]) {
        packets.append(contentsOf: newPackets)
        StorageManager.save(packets: packets)
        
        // --- 【修正】---
        // 將每一筆新 packet 發布到 MQTT，呼叫新的、無 action 參數的函式
        for packet in newPackets {
            mqttManager.publishLog(packet)
        }
    }

    /// 刪除一筆日誌（同時會發布刪除指令到 MQTT）
    func delete(_ packet: BLEPacket) {
        if let index = packets.firstIndex(where: { $0.id == packet.id }) {
            packets.remove(at: index)
            StorageManager.save(packets: packets)
            
            // 通知 MQTT 刪除這筆日誌，呼叫新的 deleteLog 函式
            mqttManager.deleteLog(packetId: packet.identifier)
        }
    }
    
    func clearDeviceHistory(for packetID: String) {
        // 1. 根據唯一的 identifier 找到日誌在陣列中的位置
        guard let index = self.packets.firstIndex(where: { $0.id == packetID }) else {
            print("錯誤：找不到 ID 為 \(packetID) 的日誌來清除歷史。")
            return
        }
        
        // 2. 確保該日誌有 parsedData
        guard self.packets[index].parsedData != nil else {
            print("警告：ID 為 \(packetID) 的日誌沒有 parsedData，無需清除。")
            return
        }
        
        // 3. 清空 devices 陣列
        self.packets[index].parsedData?.devices.removeAll()
        
        // 4. 將 hasReachedTarget 狀態重設為 false
        self.packets[index].parsedData?.hasReachedTarget = false
        
        // 5. 儲存變更到本地
        StorageManager.save(packets: self.packets)
        
        // 6. （可選）通知 MQTT 伺服器此筆日誌已更新
        mqttManager.publishLog(self.packets[index])
        
        print("成功清除日誌 ID \(packetID) 的裝置接收狀況。")
    }
    
    /// 清除所有日誌（同時會發布刪除指令到 MQTT）
    func clear() {
        
        // 先通知 MQTT 刪除所有日誌
        for packet in packets {
            mqttManager.deleteLog(packetId: packet.identifier)
        }
        
        // 然後再清除本地資料
        packets = []
        StorageManager.save(packets: [])
    }
    
    /// 重新從本地加載資料
    func reload() {
        packets = StorageManager.load()
    }
}
