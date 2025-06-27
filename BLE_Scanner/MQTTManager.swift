//
//  MQTTManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/17.
//  最後更新 2025/06/20

import MQTTNIO
import Foundation
import UIKit
import NIOCore
import NIOPosix


class MQTTManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "未連接"
    private var mqttClient: MQTTClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let clientID = "BLE_Scanner_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
    private let host = "152.42.241.75"
    private let port = 1883
    private let username = "root"
    private let password = "RwWq2LB-^^JR%+s"
    
    // MARK: - 主題定義
    private let pressureUploadTopic = "pressure/offset/upload"
    private let pressureDeleteTopic = "pressure/offset/delete"
    private let pressureDownloadTopic = "pressure/offset/download"
    private let pressureRequestTopic = "pressure/offset/request"
    
    private let logUploadTopic = "log/scanner/upload"
    private let logDeleteTopic = "log/scanner/delete"
    private let logDownloadTopic = "log/scanner/download"
    private let logRequestTopic = "log/scanner/request"
    
    private let suggestionUploadTopic = "suggestion/{type}/upload"
    private let suggestionDeleteTopic = "suggestion/{type}/delete"
    private let suggestionDownloadTopic = "suggestion/{type}/download"
    private let suggestionRequestTopic = "suggestion/{type}/request"
    
    private enum UserDefaultsKeys {
        static let maskSuggestions = "maskSuggestions"
        static let dataSuggestions = "dataSuggestions"
    }
    
    // MARK: - 回調與發布屬性
    var onOffsetReceived: ((PressureOffset) -> Void)?
    var onOffsetDeleted: ((String) -> Void)?
    var onLogReceived: ((BLEPacket) -> Void)?
    var onLogDeleted: ((String) -> Void)?
    
    @Published var maskSuggestions: [String] = []
    @Published var dataSuggestions: [String] = []
    
    private let mqttQueue = DispatchQueue(label: "mqtt.queue", qos: .userInitiated)
    
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
    
    
    init() {
        loadSuggestionsFromLocal()
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
        mqttClient = nil
        
        if let eventLoopGroup = eventLoopGroup {
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performConnect()
        }
    }
    
    private func performConnect() {
        guard let mqttClient = mqttClient else {
           print("MQTT 客戶端未初始化，正在重新初始化...")
           performSetupMQTT()
           
           DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
               self.performConnect()
           }
           return
       }
        
        DispatchQueue.main.async {
            self.connectionStatus = "連接中..."
        }
        
        mqttClient.connect().whenComplete { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isConnected = true
                    self?.connectionStatus = "已連接"
                    print("MQTT 連接成功")
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.setupListenersAndSubscribe()
                        self?.requestAllInitialData()
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
        
        mqttClient.addPublishListener(named: "MessageHandler") { [weak self] result in
            switch result {
            case .success(let publishInfo):
                // 使用增強版處理器
                self?.enhancedHandleReceivedMessage(publishInfo)
            case .failure(let error):
                print("收到訊息時發生錯誤: \(error)")
            }
        }
        
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
            // 壓力校正主題
            MQTTSubscribeInfo(topicFilter: pressureDownloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(pressureRequestTopic)/response", qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: pressureDeleteTopic, qos: .atLeastOnce),
            // 掃描 Log 主題
            MQTTSubscribeInfo(topicFilter: logDownloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(logRequestTopic)/response", qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: logDeleteTopic, qos: .atLeastOnce),
            
            // Suggestion 主題 (使用通配符+)
            MQTTSubscribeInfo(topicFilter: "suggestion/+/download", qos: .atLeastOnce)
        ]
        
        mqttClient.subscribe(to: subscriptions).whenComplete { result in
            switch result {
            case .success(let subAckReturnCodes):
                print("訂閱成功，返回碼: \(subAckReturnCodes)")
            case .failure(let error):
                print("訂閱失敗: \(error)")
            }
        }
        
        printSubscribedTopics() // 印所有訂閱的主題
    }
    
    // MARK: - 發布訊息 (壓力校正)
    func publishOffset(_ pressureOffset: PressureOffset) {
        let payloadString = "\(pressureOffset.deviceId),\(pressureOffset.baseAltitude),\(pressureOffset.offset)"
        publish(to: pressureUploadTopic, payload: payloadString)
    }

    func deleteOffset(deviceId: String) {
        // 刪除時，只發送 deviceId 即可
        publish(to: pressureDeleteTopic, payload: deviceId)
    }
    
    func requestAllOffsets() {
        // 請求時，發送自己的客戶端 ID
        publish(to: pressureRequestTopic, payload: clientID)
    }

    // MARK: - 發布訊息 (掃描 Log)
    func publishLog(_ packet: BLEPacket) {
        let timestampString = MQTTManager.logDateFormatter.string(from: packet.timestamp)
        let payloadString = "\(packet.rawData),\(packet.rssi),\(timestampString)"
        publish(to: logUploadTopic, payload: payloadString)
    }

    func deleteLog(packetId: String) {
        // 刪除時，發送 packet 的 ID (UUID 字串)
        publish(to: logDeleteTopic, payload: packetId)
    }
    
    func requestAllLogs() {
        publish(to: logRequestTopic, payload: clientID)
    }
    
    
    // MARK: - 發布訊息 (Suggestion)
    func publishSuggestion(suggestion: String, typeKey: String, action: String) {
        let topic: String
        switch action {
        case "add":
            topic = suggestionUploadTopic.replacingOccurrences(of: "{type}", with: typeKey)
        case "delete":
            topic = suggestionDeleteTopic.replacingOccurrences(of: "{type}", with: typeKey)
        default:
            print("未知的 suggestion action: \(action)")
            return
        }
        publish(to: topic, payload: suggestion)
    }

    func requestSuggestions(typeKey: String) {
        let topic = suggestionRequestTopic.replacingOccurrences(of: "{type}", with: typeKey)
        publish(to: topic, payload: clientID)
    }
    
    // MARK: - 請求所有初始資料
    func requestAllInitialData() {
        requestAllOffsets()
        requestAllLogs()
        requestSuggestions(typeKey: "mask")
        requestSuggestions(typeKey: "data")
    }
    
    // MARK: - 錯誤處理
    private func handleMQTTOperationFailure(_ error: Error) {
        DispatchQueue.main.async {
           self.isConnected = false
           self.connectionStatus = "連接中斷: \(error.localizedDescription)"
        }
    }

    // MARK: - Handle Offset Messages
    private func handleOffsetUpdate(fromString payloadString: String) {
       // 收到的格式是 "id1,val1,off1,id2,val2,off2,..."
       let components = payloadString.split(separator: ",").map { String($0) }
       
       // 每 3 個為一組
       guard components.count % 3 == 0 else {
           print("   ❌ 壓力校正訊息格式錯誤，元件數量不是 3 的倍數: \(components.count)")
           return
       }
       
       // 使用 stride 依序處理每組資料
       for i in stride(from: 0, to: components.count, by: 3) {
           let deviceId = components[i].trimmingCharacters(in: .whitespaces)
           guard let baseAltitude = Double(components[i+1].trimmingCharacters(in: .whitespaces)),
                 let offset = Double(components[i+2].trimmingCharacters(in: .whitespaces)) else {
               print("   ❌ 無法解析壓力校正數值: \(components[i+1]), \(components[i+2])")
               continue // 繼續處理下一組
           }
           
           let pressureOffset = PressureOffset(
               deviceId: deviceId,
               offset: offset,
               baseAltitude: baseAltitude,
               timestamp: Date() // 時間戳使用當前時間
           )
           
           DispatchQueue.main.async {
               self.onOffsetReceived?(pressureOffset)
           }
       }
   }
    

    // MARK: - Handle Log Messages
    private func handleLogUpdate(fromString payloadString: String) {
        // 收到的格式是 "FFFF..., -50, 2025-01-29 18:44 ,1111..., -43, 2025-07-01 15:24"
        let components = payloadString.split(separator: ",").map { String($0) }
        
        guard components.count % 3 == 0 else {
            print("   ❌ log訊息格式錯誤，元件數量不是 3 的倍數: \(components.count)")
            return
        }
        
        for i in stride(from: 0, to: components.count, by: 3) {
            let rawData = components[i].trimmingCharacters(in: .whitespaces)
            guard let rssi = Int(components[i+1].trimmingCharacters(in: .whitespaces)),
                  let timestamp = MQTTManager.logDateFormatter.date(from: components[i+2].trimmingCharacters(in: .whitespaces)) else {
                print("   ❌ 無法解析log數值: \(components[i+1]), \(components[i+2])")
                continue // 繼續處理下一組
            }
            
            let partialPacket = BLEPacket(
                id: UUID(),
                deviceID: "N/A (from MQTT)", // Device ID 未知
                identifier: "",
                deviceName: "",
                rssi: rssi,
                rawData: rawData,
                mask: "",
                data: "",
                isMatched: false,
                timestamp: timestamp,
                parsedData: nil
            )
            
            DispatchQueue.main.async {
                self.onLogReceived?(partialPacket)
            }
        }
    }


    private func loadSuggestionsFromLocal() {
        // 載入 mask suggestions
        if let savedMaskSuggestions = UserDefaults.standard.array(forKey: UserDefaultsKeys.maskSuggestions) as? [String] {
            self.maskSuggestions = savedMaskSuggestions
        }
        
        // 載入 data suggestions
        if let savedDataSuggestions = UserDefaults.standard.array(forKey: UserDefaultsKeys.dataSuggestions) as? [String] {
            self.dataSuggestions = savedDataSuggestions
        }
        
        print("📱 已載入本地 Suggestions:")
        print("   - Mask: \(maskSuggestions.count) 項")
        print("   - Data: \(dataSuggestions.count) 項")
    }
    
    private func handleOffsetDelete(fromString payloadString: String) {
        let deviceId = payloadString.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.async { self.onOffsetDeleted?(deviceId) }
    }

    private func handleLogDelete(fromString payloadString: String) {
        let packetId = payloadString.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.async { self.onLogDeleted?(packetId) }
    }

    private func publish(to topic: String, payload: String) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送訊息到主題: \(topic)")
            return
        }
        
        let buffer = ByteBuffer(string: payload)
        mqttClient.publish(to: topic, payload: buffer, qos: .atLeastOnce).whenComplete { result in
            switch result {
            case .success:
                print("訊息發送成功 -> 主題: \(topic), 內容: \(payload)")
            case .failure(let error):
                print("訊息發送失敗 -> 主題: \(topic), 錯誤: \(error)")
            }
        }
    }
    
    //MARK: - 本地儲存
    // 保存 mask suggestions 到本地
    private func saveMaskSuggestionsToLocal() {
        UserDefaults.standard.set(maskSuggestions, forKey: UserDefaultsKeys.maskSuggestions)
        print("已保存 Mask Suggestions 到本地: \(maskSuggestions.count) 項")
    }
    
    //保存 data suggestions 到本地
    private func saveDataSuggestionsToLocal() {
        UserDefaults.standard.set(dataSuggestions, forKey: UserDefaultsKeys.dataSuggestions)
        print("已保存 Data Suggestions 到本地: \(dataSuggestions.count) 項")
    }
    
    // 清除本地存儲的 suggestions
    func clearLocalSuggestions() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.maskSuggestions)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.dataSuggestions)
        
        maskSuggestions.removeAll()
        dataSuggestions.removeAll()
        
        print("已清除所有本地 Suggestions")
    }
}

// MARK: - 調試方法
extension MQTTManager {
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
    
    func sendTestMessage() {
        print("🧪 發送測試訊息...")
        
        let testOffset = PressureOffset(
            deviceId: "0\(Int.random(in: 1...9))",
            offset: Double.random(in: -50...50),
            baseAltitude: Double.random(in: 0...1000)
        )
        
        publishOffset(testOffset)
        print("   - 測試偏差值訊息已發送: \(testOffset.deviceId)")
    }

    func sendTestLogMessage() {
        print("🧪 發送測試 Log 訊息...")

        let testPacket = BLEPacket(
            deviceID: "TestDevice_\(Int.random(in: 1...9))",
            identifier: UUID().uuidString,
            deviceName: "Test Device",
            rssi: -Int.random(in: 40...80),
            rawData: "TEST_RAW_DATA",
            mask: "FF",
            data: "TEST_DATA",
            isMatched: true,
            timestamp: Date()
        )
        publishLog(testPacket)
        print("   - 測試 Log 訊息已發送: \(testPacket.deviceID)")
    }
    
    
    func printSubscribedTopics() {
        print("📡 已訂閱的主題:")
        print("   - 壓力校正下載: \(pressureDownloadTopic)")
        print("   - 壓力校正請求回應: \(pressureRequestTopic)/response")
        print("   - Log 下載: \(logDownloadTopic)")
        print("   - Log 請求回應: \(logRequestTopic)/response")
    }
}

// MARK: - 增強的訊息處理
extension MQTTManager {
    private func enhancedHandleReceivedMessage(_ publishInfo: MQTTPublishInfo) {
        let topic = publishInfo.topicName
        let payload = publishInfo.payload
        
        print("📨 [MQTT] 收到訊息")
        print("   - 主題: \(topic)")
        print("   - 時間: \(Date())")
        
        guard let payloadString = payload.getString(at: 0, length: payload.readableBytes) else {
            print("   ❌ 無法將載荷解析為字串")
            return
        }
        print("   - 內容: \(payloadString)")

        // 根據主題分派給不同的純文字處理器
        switch topic {
        case pressureDownloadTopic, "\(pressureRequestTopic)/response":
            handleOffsetUpdate(fromString: payloadString)
        
        case pressureDeleteTopic:
            // 新增：處理壓力校正刪除
            handleOffsetDelete(fromString: payloadString)
            
        case logDownloadTopic, "\(logRequestTopic)/response":
            handleLogUpdate(fromString: payloadString)
            
        case logDeleteTopic:
            // 新增：處理日誌刪除
            handleLogDelete(fromString: payloadString)
            
        default:
            if topic.contains("suggestion/") {
                handleSuggestionMessage(topic: topic, payloadString: payloadString)
            } else {
                print("   ⚠️ 未知主題群組或不需處理的主題: \(topic)")
            }
        }
    }
    
    // (handleSuggestionMessage 維持不變)
    private func handleSuggestionMessage(topic: String, payloadString: String) {
        let suggestions = payloadString.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        print("   ✅ Suggestion 訊息解析成功: \(suggestions.count) items")

        DispatchQueue.main.async {
            if topic.contains("/mask/") {
                if self.maskSuggestions != suggestions {
                    self.maskSuggestions = suggestions
                }
            } else if topic.contains("/data/") {
                if self.dataSuggestions != suggestions {
                    self.dataSuggestions = suggestions
                }
            }
        }
    }
}
