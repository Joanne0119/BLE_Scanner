//
//  MQTTDebugView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/17.
//  最後更新 2025/07/17

import SwiftUI
import Combine

struct MQTTDebugView: View {
    @ObservedObject var mqttManager: MQTTManager
    @State private var receivedMessages: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // ... (連接狀態和控制按鈕不變) ...
            
            // 接收到的訊息日誌
            VStack(alignment: .leading) {
                Text("接收到的訊息 (最新 20 筆)")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(receivedMessages.reversed(), id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .onAppear {
            setupMQTTCallbacks()
        }
        // --- 新增：監聽 Suggestion 的變化 ---
        .onReceive(mqttManager.$maskSuggestions) { newMasks in
            addMessage("✅ Mask Suggestions 更新: \(newMasks.count) 項")
        }
        .onReceive(mqttManager.$dataSuggestions) { newData in
            addMessage("✅ Data Suggestions 更新: \(newData.count) 項")
        }
    }
    
    private func addMessage(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        receivedMessages.append("[\(timestamp)] \(message)")
        
        // 保持最新的20條訊息
        if receivedMessages.count > 20 {
            receivedMessages.removeFirst()
        }
    }
    
    private func setupMQTTCallbacks() {
        // 設置接收 Offset 的回調
        mqttManager.onOffsetReceived = { [self] offset in
            addMessage("✅ 接收 Offset: \(offset.deviceId) (偏差: \(offset.offset))")
        }
        
        // --- 新增：設置接收 Log 的回調 ---
        mqttManager.onLogReceived = { [self] packet in
            addMessage("✅ 接收 Log: \(packet.rawData.prefix(10))... (RSSI: \(packet.rssi))")
        }
        
        // --- 新增：設置接收刪除指令的回調 ---
        mqttManager.onOffsetDeleted = { [self] deviceId in
            addMessage("🗑️ 刪除 Offset 指令: \(deviceId)")
        }
        
        mqttManager.onLogDeleted = { [self] packetId in
            addMessage("🗑️ 刪除 Log 指令: \(packetId)")
        }
    }
}
