//
//  MQTTManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/17.
//  最後更新 2025/06/19

import MQTTNIO
import Foundation
import UIKit
import NIOCore
import NIOPosix

// MQTT 訊息結構
struct MQTTOffsetMessage: Codable {
    let deviceId: String
    let offset: Double
    let baseAltitude: Double
    let calibrationTime: String
    let action: String // "update", "delete", "request"
    
    init(from pressureOffset: PressureOffset, action: String = "update") {
        self.deviceId = pressureOffset.deviceId
        self.offset = pressureOffset.offset
        self.baseAltitude = pressureOffset.baseAltitude
        self.calibrationTime = ISO8601DateFormatter().string(from: pressureOffset.calibrationTime)
        self.action = action
    }
}

class MQTTManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "未連接"
    
    private var mqttClient: MQTTClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let clientID = "BLE_Scanner_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
    
    // MQTT 設定
    private let host = "152.42.241.75"  // MQTT Broker 地址
    private let port = 1883
    private let username = "root"     // 用戶名
    private let password = "RwWq2LB-^^JR%+s"     // 密碼
    
    // 主題設定
    private let uploadTopic = "pressure/offset/upload"
    private let downloadTopic = "pressure/offset/download"
    private let requestTopic = "pressure/offset/request"
    
    // 回調函數
    var onOffsetReceived: ((PressureOffset) -> Void)?
    var onOffsetDeleted: ((String) -> Void)?
    
    private let mqttQueue = DispatchQueue(label: "mqtt.queue", qos: .userInitiated)
        
    
    init() {
        setupMQTT()
    }
    
    deinit {
        disconnect()
        if let eventLoopGroup = eventLoopGroup {
            DispatchQueue.global(qos: .background).async {
                try? eventLoopGroup.syncShutdownGracefully()
            }
        }
    }
    
    // MARK: - MQTT 設定
    private func setupMQTT() {
        mqttQueue.async { [weak self] in
            self?.performSetupMQTT()
        }
    }
    
    private func performSetupMQTT() {
        // 清理舊的資源
        cleanupResources()
        
        // 創建新的 EventLoopGroup
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        guard let eventLoopGroup = eventLoopGroup else {
            print("無法創建 EventLoopGroup")
            DispatchQueue.main.async {
                self.connectionStatus = "初始化失敗"
            }
            return
        }
        
        // 創建 MQTT 客戶端配置
        let configuration = MQTTClient.Configuration(
            keepAliveInterval: .seconds(60),
            userName: username,
            password: password
        )
        
        mqttClient = MQTTClient(
            host: host,
            port: port,
            identifier: clientID,
            eventLoopGroupProvider: .createNew,
            configuration: configuration
        )
        
        print("MQTT 客戶端初始化成功")
        
        DispatchQueue.main.async {
            self.connectionStatus = "已初始化"
        }
    }
    
    private func cleanupResources() {
        // 在當前線程清理
        mqttClient = nil
        
        if let eventLoopGroup = eventLoopGroup {
            // 異步關閉 EventLoopGroup
            eventLoopGroup.shutdownGracefully { error in
                if let error = error {
                    print("EventLoopGroup 關閉錯誤: \(error)")
                } else {
                    print("EventLoopGroup 已成功關閉")
                }
            }
            self.eventLoopGroup = nil
        }
    }
    
    // MARK: - 連接管理
    func connect() {
        // 確保在後台線程執行連接
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performConnect()
        }
    }
    
    private func performConnect() {
        guard let mqttClient = mqttClient else {
           print("MQTT 客戶端未初始化，正在重新初始化...")
           performSetupMQTT()
           
           // 等待初始化完成後重試
           DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
               self.performConnect()
           }
           return
       }
        
        DispatchQueue.main.async {
            self.connectionStatus = "連接中..."
        }
        
        // 連接到 MQTT Broker
        mqttClient.connect().whenComplete { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isConnected = true
                    self?.connectionStatus = "已連接"
                    print("MQTT 連接成功")
                    
                    // 連接成功後設置監聽器和訂閱
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.setupListenersAndSubscribe()
                    }
                    
                case .failure(let error):
                    self?.isConnected = false
                    self?.connectionStatus = "連接失敗: \(error.localizedDescription)"
                    print("MQTT 連接失敗: \(error)")
                }
            }
        }
    }
    
    private func setupListenersAndSubscribe() {
        guard let mqttClient = mqttClient else { return }
        
        // 設定訊息接收處理
        mqttClient.addPublishListener(named: "MessageHandler") { [weak self] result in
            switch result {
            case .success(let publishInfo):
                self?.handleReceivedMessage(publishInfo)
            case .failure(let error):
                print("收到訊息時發生錯誤: \(error)")
            }
        }
        
        // 訂閱主題
        subscribeToTopics()
    }
    
    func disconnect() {
        guard let mqttClient = mqttClient else { return }
        
        mqttClient.disconnect().whenComplete { [weak self] result in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.connectionStatus = "已斷開"
            }
            
            switch result {
            case .success:
                print("MQTT 斷開連接成功")
            case .failure(let error):
                print("MQTT 斷開連接失敗: \(error)")
            }
        }
    }
    
    // MARK: - 訂閱主題
    private func subscribeToTopics() {
        guard let mqttClient = mqttClient, isConnected else { return }
        
        let subscriptions = [
            MQTTSubscribeInfo(topicFilter: downloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(requestTopic)/response", qos: .atLeastOnce)
        ]
        
        mqttClient.subscribe(to: subscriptions).whenComplete { result in
            switch result {
            case .success(let subAckReturnCodes):
                print("訂閱成功，返回碼: \(subAckReturnCodes)")
            case .failure(let error):
                print("訂閱失敗: \(error)")
            }
        }
        
        print("已訂閱主題: \(downloadTopic), \(requestTopic)/response")
    }
    
    // MARK: - 發布訊息
    func publishOffset(_ pressureOffset: PressureOffset) {
        // 確保在後台線程執行發布
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performPublishOffset(pressureOffset)
        }
    }
    
    private func performPublishOffset(_ pressureOffset: PressureOffset) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送訊息")
            DispatchQueue.main.async {
                self.connectionStatus = "未連接"
                self.isConnected = false
            }
            return
        }
        
        let message = MQTTOffsetMessage(from: pressureOffset, action: "update")
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            let payload = ByteBuffer(data: jsonData)
            
            mqttClient.publish(
                to: uploadTopic,
                payload: payload,
                qos: .atLeastOnce
            ).whenComplete { [weak self] result in
                switch result {
                case .success:
                    print("發送偏差值更新成功: \(pressureOffset.deviceId)")
                case .failure(let error):
                    print("發送偏差值更新失敗: \(error)")
                    self?.handleMQTTOperationFailure(error)
                }
            }
        } catch {
            print("JSON 編碼失敗: \(error)")
        }
    }
    
    func deleteOffset(deviceId: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performDeleteOffset(deviceId: deviceId)
        }
    }
    
    private func performDeleteOffset(deviceId: String) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送訊息")
            return
        }
        
        let messagePressureOffset = PressureOffset(deviceId: deviceId,
                                                   offset: 0,
                                                   baseAltitude: 0)
        
        let message = MQTTOffsetMessage(
            from: messagePressureOffset,
            action: "delete"
        )
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            let payload = ByteBuffer(data: jsonData)
            
            mqttClient.publish(
                to: uploadTopic,
                payload: payload,
                qos: .atLeastOnce
            ).whenComplete { result in
                switch result {
                case .success:
                    print("發送偏差值刪除成功: \(deviceId)")
                case .failure(let error):
                    print("發送偏差值刪除失敗: \(error)")
                }
            }
        } catch {
            print("JSON 編碼失敗: \(error)")
        }
    }
    
    func requestAllOffsets() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performRequestAllOffsets()
        }
    }
    
    private func performRequestAllOffsets() {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送請求")
            return
        }
        
        let messagePressureOffset = PressureOffset(deviceId: "ALL",
                                                   offset: 0,
                                                   baseAltitude: 0)
        
        let message = MQTTOffsetMessage(
            from: messagePressureOffset,
            action: "request"
        )
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            let payload = ByteBuffer(data: jsonData)
            
            mqttClient.publish(
                to: requestTopic,
                payload: payload,
                qos: .atLeastOnce
            ).whenComplete { result in
                switch result {
                case .success:
                    print("請求所有偏差值成功")
                case .failure(let error):
                    print("請求所有偏差值失敗: \(error)")
                }
            }
        } catch {
            print("JSON 編碼失敗: \(error)")
        }
    }
    
    // MARK: - 錯誤處理
   private func handleMQTTOperationFailure(_ error: Error) {
       DispatchQueue.main.async {
           self.isConnected = false
           self.connectionStatus = "連接中斷: \(error.localizedDescription)"
       }
   }
    
    // MARK: - 處理接收到的訊息
    private func handleReceivedMessage(_ publishInfo: MQTTPublishInfo) {
        let topic = publishInfo.topicName
        let payload = publishInfo.payload
        
        guard let jsonString = payload.getString(at: 0, length: payload.readableBytes) else {
            print("無法解析訊息內容")
            return
        }
        
        print("收到訊息 from \(topic): \(jsonString)")
        
        do {
            let jsonData = jsonString.data(using: .utf8) ?? Data()
            let mqttMessage = try JSONDecoder().decode(MQTTOffsetMessage.self, from: jsonData)
            
            switch mqttMessage.action {
            case "update":
                handleOffsetUpdate(mqttMessage)
            case "delete":
                handleOffsetDelete(mqttMessage)
            case "response":
                handleOffsetResponse(mqttMessage)
            default:
                print("未知的動作: \(mqttMessage.action)")
            }
            
        } catch {
            print("JSON 解析失敗: \(error)")
        }
    }
    
    private func handleOffsetUpdate(_ message: MQTTOffsetMessage) {
        // 轉換為 PressureOffset
        let dateFormatter = ISO8601DateFormatter()
        let calibrationTime = dateFormatter.date(from: message.calibrationTime) ?? Date()
        
        let pressureOffset = PressureOffset(
            deviceId: message.deviceId,
            offset: message.offset,
            baseAltitude: message.baseAltitude
        )
        
        // 創建包含正確校正時間的偏差值
        let updatedOffset = PressureOffset(
            deviceId: pressureOffset.deviceId,
            offset: pressureOffset.offset,
            baseAltitude: pressureOffset.baseAltitude
        )
        
        DispatchQueue.main.async {
            self.onOffsetReceived?(updatedOffset)
        }
    }
    
    private func handleOffsetDelete(_ message: MQTTOffsetMessage) {
        DispatchQueue.main.async {
            self.onOffsetDeleted?(message.deviceId)
        }
    }
    
    private func handleOffsetResponse(_ message: MQTTOffsetMessage) {
        // 處理請求回應，與 update 相同
        handleOffsetUpdate(message)
    }
}
extension MQTTManager {
    
    // MARK: - 調試方法
    
    /// 測試連接狀態
    func testConnection() {
        print("🔍 測試 MQTT 連接狀態...")
        print("   - 連接狀態: \(isConnected ? "已連接" : "未連接")")
        print("   - 客戶端ID: \(clientID)")
        print("   - Broker: \(host):\(port)")
        print("   - 狀態訊息: \(connectionStatus)")
        
        if let client = mqttClient {
            print("   - 客戶端已初始化: ✅")
        } else {
            print("   - 客戶端未初始化: ❌")
        }
    }
    
    /// 發送測試訊息
    func sendTestMessage() {
        print("🧪 發送測試訊息...")
        
        let testOffset = PressureOffset(
            deviceId: "0\(Int.random(in: 1...9))",
            offset: Double.random(in: -50...50),
            baseAltitude: Double.random(in: 0...1000)
        )
        
        publishOffset(testOffset)
        print("   - 測試訊息已發送: \(testOffset.deviceId)")
    }
    
    /// 請求所有資料並顯示結果
    func testRequestAllData() {
        print("📥 測試請求所有資料...")
        
        // 設置臨時回調來顯示接收到的資料
        let originalCallback = onOffsetReceived
        
        onOffsetReceived = { [weak self] offset in
            print("   ✅ 接收到資料: \(offset.deviceId)")
            print("      - 偏差值: \(offset.offset)")
            print("      - 基準海拔: \(offset.baseAltitude)")
            print("      - 校正時間: \(offset.calibrationTime)")
            
            // 呼叫原始回調
            originalCallback?(offset)
        }
        
        requestAllOffsets()
    }
    
    /// 打印所有訂閱的主題
    func printSubscribedTopics() {
        print("📡 訂閱的主題:")
        print("   - 下載主題: \(downloadTopic)")
        print("   - 請求回應主題: \(requestTopic)/response")
    }
}

// MARK: - 增強的訊息處理（替換原有的 handleReceivedMessage）
extension MQTTManager {
    
    /// 增強版訊息處理，包含更詳細的日誌
    private func enhancedHandleReceivedMessage(_ publishInfo: MQTTPublishInfo) {
        let topic = publishInfo.topicName
        let payload = publishInfo.payload
        
        // 詳細日誌
        print("📨 [MQTT] 收到訊息")
        print("   - 主題: \(topic)")
        print("   - 載荷大小: \(payload.readableBytes) bytes")
        print("   - 時間: \(Date())")
        
        guard let jsonString = payload.getString(at: 0, length: payload.readableBytes) else {
            print("   ❌ 無法解析載荷內容")
            return
        }
        
        print("   - 內容: \(jsonString)")
        
        do {
            let jsonData = jsonString.data(using: .utf8) ?? Data()
            let mqttMessage = try JSONDecoder().decode(MQTTOffsetMessage.self, from: jsonData)
            
            print("   ✅ JSON 解析成功")
            print("      - 設備ID: \(mqttMessage.deviceId)")
            print("      - 動作: \(mqttMessage.action)")
            print("      - 偏差值: \(mqttMessage.offset)")
            
            switch mqttMessage.action {
            case "update":
                print("   🔄 處理更新動作")
                handleOffsetUpdate(mqttMessage)
            case "delete":
                print("   🗑️ 處理刪除動作")
                handleOffsetDelete(mqttMessage)
            case "response":
                print("   📤 處理回應動作")
                handleOffsetResponse(mqttMessage)
            default:
                print("   ⚠️ 未知動作: \(mqttMessage.action)")
            }
            
        } catch {
            print("   ❌ JSON 解析失敗: \(error)")
            print("   原始內容: \(jsonString)")
        }
    }
}
