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

// MARK: - Message Structures

// MQTT 壓力校正訊息結構
struct MQTTOffsetMessage: Codable {
    let deviceId: String
    let offset: Double
    let baseAltitude: Double
    let timestamp: String
    let action: String // "update", "delete", "request", "response"

    init(from pressureOffset: PressureOffset, action: String = "update") {
        self.deviceId = pressureOffset.deviceId
        self.offset = pressureOffset.offset
        self.baseAltitude = pressureOffset.baseAltitude
        self.timestamp = ISO8601DateFormatter().string(from: pressureOffset.timestamp)
        self.action = action
    }
}

// MQTT 掃描 Log 訊息結構 (包含解析後的資料)
struct MQTTLogMessage: Codable {
    let id: String
    let deviceID: String
    let rssi: Int
    let rawData: String
    let timestamp: String
    let action: String // "upload", "delete", "request", "response"
    let parsedData: ParsedBLEData? // 包含解析後的資料
    
    // 從 BLEPacket 初始化
    init(from packet: BLEPacket, action: String = "upload") {
        self.id = packet.id.uuidString
        self.deviceID = packet.deviceID
        self.rssi = packet.rssi
        self.rawData = packet.rawData
        self.timestamp = ISO8601DateFormatter().string(from: packet.timestamp)
        self.action = action
        self.parsedData = packet.parsedData // 賦值
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
    
    // MARK: - 主題設定
    // 壓力校正主題
    private let uploadTopic = "pressure/offset/upload"
    private let downloadTopic = "pressure/offset/download"
    private let requestTopic = "pressure/offset/request"
    
    // 掃描 Log 主題
    private let logUploadTopic = "log/scanner/upload"
    private let logDownloadTopic = "log/scanner/download"
    private let logRequestTopic = "log/scanner/request"
    
    // Suggestion 主題
    private let suggestionUploadTopic = "suggestion/{type}/upload"
    private let suggestionDeleteTopic = "suggestion/{type}/delete"
    private let suggestionDownloadTopic = "suggestion/{type}/download"
    private let suggestionRequestTopic = "suggestion/{type}/request"
    
    // MARK: - UserDefaults Keys
    private enum UserDefaultsKeys {
        static let maskSuggestions = "maskSuggestions"
        static let dataSuggestions = "dataSuggestions"
    }
    
    // MARK: - 回調函數
    // 壓力校正回調
    var onOffsetReceived: ((PressureOffset) -> Void)?
    var onOffsetDeleted: ((String) -> Void)?
    
    // 掃描 Log 回調
    var onLogReceived: ((BLEPacket) -> Void)?
    var onLogDeleted: ((String) -> Void)?
    
    // Suggestion 回調
    @Published var maskSuggestions: [String] = [] {
        didSet {
            // 當 maskSuggestions 改變時自動保存到本地
            saveMaskSuggestionsToLocal()
        }
    }
    
    @Published var dataSuggestions: [String] = [] {
        didSet {
            // 當 dataSuggestions 改變時自動保存到本地
            saveDataSuggestionsToLocal()
        }
    }
    
    private let mqttQueue = DispatchQueue(label: "mqtt.queue", qos: .userInitiated)
        
    
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
            MQTTSubscribeInfo(topicFilter: downloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(requestTopic)/response", qos: .atLeastOnce),
            // 掃描 Log 主題
            MQTTSubscribeInfo(topicFilter: logDownloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(logRequestTopic)/response", qos: .atLeastOnce),
            
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

    // MARK: - 發布訊息 (掃描 Log)
    func publishLog(_ packet: BLEPacket, action: String = "upload") {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performPublishLog(packet, action: action)
        }
    }

    private func performPublishLog(_ packet: BLEPacket, action: String) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送 Log")
            return
        }
        
        let message = MQTTLogMessage(from: packet, action: action)
        let topic = (action == "delete") ? logUploadTopic : logUploadTopic // Deletes also go to the upload topic with a "delete" action
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            let payload = ByteBuffer(data: jsonData)
            
            mqttClient.publish(to: topic, payload: payload, qos: .atLeastOnce).whenComplete { result in
                switch result {
                case .success:
                    print("Log \(action) 成功: \(packet.id.uuidString)")
                case .failure(let error):
                    print("Log \(action) 失敗: \(error)")
                }
            }
        } catch {
            print("Log JSON 編碼失敗: \(error)")
        }
    }
    
    func requestAllLogs() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performRequestAllLogs()
        }
    }
    

    private func performRequestAllLogs() {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送請求")
            return
        }

        // Create a dummy packet for the request message
        let dummyPacket = BLEPacket(id: UUID(), deviceID: "ALL", identifier: "", deviceName: "", rssi: 0, rawData: "", mask: "", data: "", isMatched: false, timestamp: Date(), parsedData: nil)
        let message = MQTTLogMessage(from: dummyPacket, action: "request")
        
        do {
            let jsonData = try JSONEncoder().encode(message)
            let payload = ByteBuffer(data: jsonData)
            
            mqttClient.publish(to: logRequestTopic, payload: payload, qos: .atLeastOnce).whenComplete { result in
                switch result {
                case .success:
                    print("請求所有 Log 成功")
                case .failure(let error):
                    print("請求所有 Log 失敗: \(error)")
                }
            }
        } catch {
            print("JSON 編碼失敗: \(error)")
        }
    }
    
    // MARK: - 發布訊息 (Suggestion)
    func publishSuggestion(suggestion: String, typeKey: String, action: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performPublishSuggestion(suggestion: suggestion, typeKey: typeKey, action: action)
        }
    }

    private func performPublishSuggestion(suggestion: String, typeKey: String, action: String) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法發送 Suggestion")
            return
        }
        
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
        
        let payload = ByteBuffer(string: suggestion)
        
        mqttClient.publish(to: topic, payload: payload, qos: .atLeastOnce).whenComplete { result in
            switch result {
            case .success:
                print("發送 Suggestion '\(action)' 成功: \(suggestion) 到主題 \(topic)")
            case .failure(let error):
                print("發送 Suggestion '\(action)' 失敗: \(error)")
            }
        }
    }

    func requestSuggestions(typeKey: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performRequestSuggestions(typeKey: typeKey)
        }
    }

    private func performRequestSuggestions(typeKey: String) {
        guard let mqttClient = mqttClient, isConnected else {
            print("MQTT 未連接，無法請求 Suggestion")
            return
        }
        
        let topic = suggestionRequestTopic.replacingOccurrences(of: "{type}", with: typeKey)
        let payload = ByteBuffer(string: self.clientID)
        
        mqttClient.publish(to: topic, payload: payload, qos: .atLeastOnce).whenComplete { result in
            switch result {
            case .success:
                print("請求所有 \(typeKey) suggestions 成功")
            case .failure(let error):
                print("請求所有 \(typeKey) suggestions 失敗: \(error)")
            }
        }
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
    
    // MARK: - 處理接收到的訊息 (已由 enhancedHandleReceivedMessage 取代)
    private func handleReceivedMessage(_ publishInfo: MQTTPublishInfo) {
        // 此方法已由 enhancedHandleReceivedMessage 取代，保留以備不時之需
    }

    // MARK: - Handle Offset Messages
    private func handleOffsetUpdate(_ message: MQTTOffsetMessage) {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.date(from: message.timestamp) ?? Date()
        
        // 呼叫新的 init 方法，並傳入解析好的 timestamp
        let pressureOffset = PressureOffset(
            deviceId: message.deviceId,
            offset: message.offset,
            baseAltitude: message.baseAltitude,
            timestamp: timestamp
        )
        
        DispatchQueue.main.async {
            // 現在傳遞的 pressureOffset 物件會包含來自伺服器的正確時間
            self.onOffsetReceived?(pressureOffset)
        }
    }
    
    private func handleOffsetDelete(_ message: MQTTOffsetMessage) {
        DispatchQueue.main.async {
            self.onOffsetDeleted?(message.deviceId)
        }
    }

    // MARK: - Handle Log Messages
    private func handleLogUpdate(_ message: MQTTLogMessage) {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.date(from: message.timestamp) ?? Date()
        guard let uuid = UUID(uuidString: message.id) else {
            print("無法解析 Log 的 UUID: \(message.id)")
            return
        }

        // 建立 BLEPacket 並包含從訊息中收到的 parsedData
        let packet = BLEPacket(
            id: uuid,
            deviceID: message.deviceID,
            identifier: "",
            deviceName: "",
            rssi: message.rssi,
            rawData: message.rawData,
            mask: "",
            data: "",
            isMatched: false,
            timestamp: timestamp,
            parsedData: message.parsedData 
        )

        DispatchQueue.main.async {
            self.onLogReceived?(packet)
        }
    }

    private func handleLogDelete(_ message: MQTTLogMessage) {
        DispatchQueue.main.async {
            self.onLogDeleted?(message.id)
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
    
    func testRequestAllData() {
        print("📥 測試請求所有資料...")
        
        // 請求校正資料
        requestAllOffsets()
        
        // 請求 Log 資料
        requestAllLogs()
    }
    
    func printSubscribedTopics() {
        print("📡 已訂閱的主題:")
        print("   - 壓力校正下載: \(downloadTopic)")
        print("   - 壓力校正請求回應: \(requestTopic)/response")
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
        
        // 根據主題判斷訊息類型
        if topic.contains("suggestion/") {
            // 如果是 suggestion 主題，當作純文字處理
            guard let textString = payload.getString(at: 0, length: payload.readableBytes) else {
                print("   ❌ 無法解析 suggestion 載荷內容")
                return
            }
            print("   - 內容: \(textString)")
            handleSuggestionMessage(topic: topic, payloadString: textString)

        } else if topic.contains("pressure/offset") || topic.contains("log/scanner") {
            // 如果是其他主題，才當作 JSON 處理
            guard let jsonString = payload.getString(at: 0, length: payload.readableBytes) else {
                print("   ❌ 無法解析 JSON 載荷內容")
                return
            }
            print("   - 內容: \(jsonString)")
            let jsonData = Data(jsonString.utf8)

            if topic.contains("pressure/offset") {
                handlePressureOffsetMessage(jsonData: jsonData)
            } else if topic.contains("log/scanner") {
                handleScannerLogMessage(jsonData: jsonData)
            }

        } else {
            print("   ⚠️ 未知主題群組: \(topic)")
        }
    }

    private func handlePressureOffsetMessage(jsonData: Data) {
        do {
            let message = try JSONDecoder().decode(MQTTOffsetMessage.self, from: jsonData)
            print("   ✅ 壓力校正訊息解析成功, 動作: \(message.action)")
            
            switch message.action {
            case "update", "response": // response 和 update 處理方式相同
                handleOffsetUpdate(message)
            case "delete":
                handleOffsetDelete(message)
            default:
                print("   ⚠️ 未知的壓力校正動作: \(message.action)")
            }
        } catch {
            print("   ❌ 壓力校正訊息 JSON 解析失敗: \(error)")
        }
    }

    private func handleScannerLogMessage(jsonData: Data) {
        do {
            let message = try JSONDecoder().decode(MQTTLogMessage.self, from: jsonData)
            print("   ✅ 掃描 Log 訊息解析成功, 動作: \(message.action)")

            switch message.action {
            case "upload", "response": // 雲端下載的 log 和請求回應的 log
                handleLogUpdate(message)
            case "delete":
                handleLogDelete(message)
            default:
                print("   ⚠️ 未知的 Log 動作: \(message.action)")
            }
        } catch {
            print("   ❌ 掃描 Log 訊息 JSON 解析失敗: \(error)")
        }
    }
    
    private func handleSuggestionMessage(topic: String, payloadString: String) {
        let suggestions = payloadString.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        print("   ✅ Suggestion 訊息解析成功: \(suggestions.count) items")

        DispatchQueue.main.async {
            // 使用臨時變量避免在 didSet 中重複保存
            if topic.contains("/mask/") {
                // 只有當數據真的不同時才更新（避免重複保存）
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
