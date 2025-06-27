//
//  StorageManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//  最後更新 2025/06/27

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
            self.packets.removeAll(where: { $0.id == id })
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
            
            // --- 【修正】---
            // 通知 MQTT 刪除這筆日誌，呼叫新的 deleteLog 函式
            mqttManager.deleteLog(packetId: packet.id.uuidString)
        }
    }
    
    /// 清除所有日誌（同時會發布刪除指令到 MQTT）
    func clear() {
        // --- 【修正】---
        // 先通知 MQTT 刪除所有日誌
        for packet in packets {
            mqttManager.deleteLog(packetId: packet.id.uuidString)
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
