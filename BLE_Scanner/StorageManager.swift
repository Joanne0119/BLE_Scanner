//
//  StorageManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//  最後更新 2025/06/20
//
import Foundation
import SwiftUI
import Combine

// StorageManager 負責本地存儲
struct StorageManager {
    static let storageKey = "savedPackets"

    static func save(packets: [BLEPacket]) {
        if let encoded = try? JSONEncoder().encode(packets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            // 使用 NotificationCenter 通知 UI 更新，這是一個好習慣
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

// SavedPacketsStore 被升級為同步中心
class SavedPacketsStore: ObservableObject {
    @Published var packets: [BLEPacket] = []
    
    // 持有 MQTTManager 的實例
    private var mqttManager: MQTTManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化
    // 修改 init，使其能夠接收 MQTTManager
    init(mqttManager: MQTTManager) {
        self.mqttManager = mqttManager
        // 1. 先從本地加載，讓 UI 立即顯示
        self.packets = StorageManager.load()
        // 2. 設定 MQTT 的回調，以接收遠端更新
        setupMQTTCallbacks()
        // 3. 從伺服器請求所有資料，以進行同步
        requestAllLogsFromServer()
    }

    // MARK: - MQTT 同步
    
    /// 設定 MQTT 訊息的回調處理
    private func setupMQTTCallbacks() {
        // 當從 MQTT 收到日誌時
        mqttManager.onLogReceived = { [weak self] packet in
            self?.updateLogFromMQTT(packet)
        }
        
        // 當從 MQTT 收到刪除日誌的指令時
        mqttManager.onLogDeleted = { [weak self] packetId in
            // MQTT 回傳的可能是 UUID 字串
            guard let uuid = UUID(uuidString: packetId) else { return }
            self?.deleteLogFromMQTT(id: uuid)
        }
    }
    
    /// 從伺服器請求所有歷史日誌
    func requestAllLogsFromServer() {
        // 確保 MQTT 已連接，延遲一點再發送請求
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard self?.mqttManager.isConnected == true else { return }
            self?.mqttManager.requestAllLogs()
            print("已發送請求以同步所有伺服器日誌。")
        }
    }

    /// 從 MQTT 更新或新增一筆日誌
    private func updateLogFromMQTT(_ packet: BLEPacket) {
        // 使用 main thread 更新 @Published 變數
        DispatchQueue.main.async {
            if let index = self.packets.firstIndex(where: { $0.id == packet.id }) {
                // 如果日誌已存在，則更新它
                // 僅在伺服器版本較新時更新（比較時間戳）
                if packet.timestamp > self.packets[index].timestamp {
                    self.packets[index] = packet
                }
            } else {
                // 如果是新的日誌，則新增
                self.packets.append(packet)
            }
            // 保存變更到本地
            StorageManager.save(packets: self.packets)
        }
    }

    /// 從 MQTT 刪除一筆日誌
    private func deleteLogFromMQTT(id: UUID) {
        // 使用 main thread 更新 @Published 變數
        DispatchQueue.main.async {
            self.packets.removeAll(where: { $0.id == id })
            // 保存變更到本地
            StorageManager.save(packets: self.packets)
        }
    }
    
    // MARK: - 本地操作 (已整合 MQTT)
    
    /// 新增掃描結果（同時會發布到 MQTT）
    func append(_ newPackets: [BLEPacket]) {
        packets.append(contentsOf: newPackets)
        StorageManager.save(packets: packets)
        
        // 將每一筆新 packet 發布到 MQTT
        for packet in newPackets {
            mqttManager.publishLog(packet, action: "upload")
        }
    }

    /// 刪除一筆日誌（同時會發布刪除指令到 MQTT）
    func delete(_ packet: BLEPacket) {
        if let index = packets.firstIndex(where: { $0.id == packet.id }) {
            packets.remove(at: index)
            StorageManager.save(packets: packets)
            
            // 通知 MQTT 刪除這筆日誌
            mqttManager.publishLog(packet, action: "delete")
        }
    }
    
    /// 清除所有日誌（同時會發布刪除指令到 MQTT）
    func clear() {
        // 先通知 MQTT 刪除所有日誌
        for packet in packets {
            mqttManager.publishLog(packet, action: "delete")
        }
        
        // 然後再清除本地資料
        packets = []
        StorageManager.save(packets: [])
    }
    
    /// 重新從本地加載資料 (此方法現在主要用於手動刷新)
    func reload() {
        packets = StorageManager.load()
    }
}
