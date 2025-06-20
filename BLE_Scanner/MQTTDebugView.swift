//
//  MQTTDebugView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/17.
//  最後更新 2025/06/20

import SwiftUI

struct MQTTDebugView: View {
    @ObservedObject var mqttManager: MQTTManager
    @State private var receivedMessages: [String] = []
    @State private var testResults: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // 連接狀態
            VStack {
                Text("MQTT 連接狀態")
                    .font(.headline)
                
                HStack {
                    Circle()
                        .fill(mqttManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    
                    Text(mqttManager.connectionStatus)
                        .font(.body)
                }
            }
            
            // 控制按鈕
            VStack(spacing: 10) {
                Button("測試連接") {
                    mqttManager.testConnection()
                }
                .buttonStyle(.borderedProminent)
                
                Button("發送測試訊息") {
                    mqttManager.sendTestMessage()
                }
                .buttonStyle(.bordered)
                
                Button("請求所有資料") {
                    mqttManager.testRequestAllData()
                }
                .buttonStyle(.bordered)
                
                Button("重新連接") {
                    mqttManager.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        mqttManager.connect()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // 接收到的訊息日誌
            VStack(alignment: .leading) {
                Text("接收到的訊息")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(receivedMessages.indices, id: \.self) { index in
                            Text(receivedMessages[index])
                                .font(.caption)
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
    }
    
    private func setupMQTTCallbacks() {
        // 設置接收訊息的回調
        mqttManager.onOffsetReceived = { offset in
            let message = "✅ 接收: \(offset.deviceId) (偏差: \(offset.offset))"
            receivedMessages.append(message)
            
            // 保持最新的20條訊息
            if receivedMessages.count > 20 {
                receivedMessages.removeFirst()
            }
        }
        
        mqttManager.onOffsetDeleted = { deviceId in
            let message = "🗑️ 刪除: \(deviceId)"
            receivedMessages.append(message)
        }
    }
}
