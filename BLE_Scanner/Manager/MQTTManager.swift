//
//  MQTTManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/17.
//  最後更新 2025/07/17

import MQTTNIO
import Foundation
import UIKit
import NIOCore
import NIOPosix


class MQTTManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "未連接"
    private let dataParser = BLEDataParser()
    private var mqttClient: MQTTClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let clientID = "BLE_Scanner_\(UUID().uuidString)"
    private var host = ""
    private var port = 0
    private var username = ""
    private var password = ""
    
    // MARK: - 連接監控相關
    private var connectionMonitorTimer: Timer?
    private var reconnectTimer: Timer?
    private var isReconnecting = false
    private let connectionCheckInterval: TimeInterval = 5.0  // 每5秒檢查一次
    private let reconnectInterval: TimeInterval = 3.0       // 重連間隔3秒
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    
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
    
    @Published var maskSuggestions: [String] = [] {
        didSet {
            saveMaskSuggestionsToLocal()
        }
    }
    @Published var dataSuggestions: [String] = [] {
        didSet {
            saveDataSuggestionsToLocal()
        }
    }
    
    private let mqttQueue = DispatchQueue(label: "mqtt.queue", qos: .userInitiated)
    
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
    
    
    init() {
        loadCredentials()
        loadSuggestionsFromLocal()
        setupMQTT()
        startConnectionMonitoring()
    }
    
    deinit {
        stopConnectionMonitoring()
        disconnect()
        if let eventLoopGroup = eventLoopGroup {
            DispatchQueue.global(qos: .background).async {
                try? eventLoopGroup.syncShutdownGracefully()
            }
        }
    }
    
    // MARK: - 連接監控
    private func startConnectionMonitoring() {
        stopConnectionMonitoring() // 先停止現有的監控
        
        connectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: connectionCheckInterval, repeats: true) { [weak self] _ in
            self?.checkConnectionStatus()
        }
        
        print("開始連接監控，每 \(connectionCheckInterval) 秒檢查一次")
    }
    
    private func stopConnectionMonitoring() {
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        print("停止連接監控")
    }
    
    private func checkConnectionStatus() {
        // 檢查客戶端是否存在且表面上已連接
        guard let mqttClient = mqttClient else {
            handleConnectionLost()
            return
        }
        
        // 嘗試發送一個輕量級的測試訊息來檢查連接狀態
        // 使用一個不存在的主題，這樣不會影響正常業務
        let testPayload = ByteBuffer(string: "ping")
        
        mqttClient.publish(to: "connection/test/ping", payload: testPayload, qos: .atMostOnce).whenComplete { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // 發送成功，連接正常
                    if !(self?.isConnected ?? false) {
                        self?.isConnected = true
                        self?.connectionStatus = "已連接"
                        self?.reconnectAttempts = 0
                        print("連接狀態恢復正常")
                    }
                case .failure(let error):
                    // 發送失敗，連接可能有問題
                    print("連接檢查失敗: \(error)")
                    self?.handleConnectionLost()
                }
            }
        }
    }
    
    private func handleConnectionLost() {
        DispatchQueue.main.async {
            if self.isConnected {
                self.isConnected = false
                self.connectionStatus = "連接中斷"
                print("檢測到連接中斷")
            }
        }
        
        // 開始重連流程
        startReconnectProcess()
    }
    
    private func startReconnectProcess() {
        guard !isReconnecting else { return }
        
        isReconnecting = true
        reconnectAttempts += 1
        
        DispatchQueue.main.async {
            self.connectionStatus = "重連中... (第 \(self.reconnectAttempts) 次)"
        }
        
        print("開始重連流程，第 \(reconnectAttempts) 次嘗試")
        
        // 如果超過最大重連次數，停止重連
        if reconnectAttempts > maxReconnectAttempts {
            isReconnecting = false
            DispatchQueue.main.async {
                self.connectionStatus = "重連失敗，已停止嘗試"
            }
            print("重連次數超過限制，停止重連")
            return
        }
        
        // 延遲重連
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: false) { [weak self] _ in
            self?.performReconnect()
        }
    }
    
    private func performReconnect() {
        print("執行重連...")
        
        // 先清理舊連接
        disconnect()
        
        // 重新初始化MQTT
        setupMQTT()
        
        // 延遲一下再連接
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connect()
            self.isReconnecting = false
        }
    }
    
    // MARK: - MQTT 設定
    private func loadCredentials() {
        guard let path = Bundle.main.path(forResource: "MQTTCredentials", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
            // 如果檔案不存在或格式錯誤，直接讓 App Crash，因為這是開發階段必須解決的問題
            fatalError("❌ MQTTCredentials.plist not found or is invalid.")
        }
        
        // 從字典中讀取值
        guard let host = dict["host"] as? String,
              let port = dict["port"] as? Int,
              let username = dict["username"] as? String,
              let password = dict["password"] as? String else {
            fatalError("❌ MQTTCredentials.plist is missing required keys.")
        }
        
        // 將讀取到的值賦給屬性
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        
        print("✅ MQTT 憑證載入成功")
    }
    
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
                    self?.reconnectAttempts = 0
                    print("MQTT 連接成功")
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.setupListenersAndSubscribe()
                        self?.requestAllInitialData()
                    }
                    
                case .failure(let error):
                    self?.isConnected = false
                    self?.connectionStatus = "連接失敗: \(error.localizedDescription)"
                    print("MQTT 連接失敗: \(error)")
                    
                    self?.startReconnectProcess()
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
        stopConnectionMonitoring()
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
    
    private func setupConnectionMonitoring() {
        guard let mqttClient = mqttClient else { return }
        // 監控連接狀態變化
        mqttClient.addCloseListener(named: "ConnectionMonitor") { [weak self] result in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.connectionStatus = "連接中斷"
                print("MQTT 連接已中斷")
            }
            
            self?.startReconnectProcess()
        }
    }
    
    // 手動重連方法
    func forceReconnect() {
        print("強制重連...")
        reconnectAttempts = 0
        startReconnectProcess()
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
        let testGroupID = TestSessionManager.shared.getCurrentTestID()
        let timestampString = MQTTManager.logDateFormatter.string(from: packet.timestamp)
        let finalPayloadString = "\(packet.rawData),\(packet.rssi),\(timestampString),\(testGroupID)"
        
        print("publish log with TestID: \(finalPayloadString)")
        publish(to: logUploadTopic, payload: finalPayloadString)
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
            let rawDataStr = components[i].trimmingCharacters(in: .whitespaces)
            guard let rssi = Int(components[i+1].trimmingCharacters(in: .whitespaces)),
                  let timestamp = MQTTManager.logDateFormatter.date(from: components[i+2].trimmingCharacters(in: .whitespaces)) else {
                print("   ❌ 無法解析log數值: \(components[i+1]), \(components[i+2])")
                continue // 繼續處理下一組
            }
            
            let maskLength = 13
            let dataLength = 15 // As expected by BLEDataParser
            let idLength = 1
            
            guard let rawBytes = parseHexInput(rawDataStr), rawBytes.count >= (maskLength + dataLength + idLength) else {
                print("   ❌ Raw data from MQTT is invalid or has incorrect length.")
                continue
            }
            
            // 1. Extract Mask (First 13 bytes)
            let maskBytes = Array(rawBytes.prefix(maskLength))
            let maskStr = bytesToHexString(maskBytes)
            
            // 2. Extract Device ID (Last byte)
            let idBytes = Array(rawBytes.suffix(idLength))
            // Convert byte to its decimal string representation, like in CBLEScanner
            let deviceId = idBytes.map { String($0) }.joined()

            // 3. Extract Data (The 15 bytes between mask and ID)
            let dataStartIndex = maskLength
            let dataEndIndex = rawBytes.count - idLength
            let dataBytes = Array(rawBytes[dataStartIndex..<dataEndIndex])
            let dataStr = bytesToHexString(dataBytes)

            // 4. Parse the data payload using BLEDataParser
            let parsedData = dataParser.parseDataBytes(dataBytes)
            
            let partialPacket = BLEPacket(
                deviceID: deviceId,
                identifier: UUID().uuidString, // Generate a new unique ID as peripheral's is unknown
                deviceName: "N/A (from MQTT)",
                rssi: rssi,
                rawData: rawDataStr,
                mask: maskStr,
                data: dataStr,
                isMatched: false,
                timestamp: timestamp,
                parsedData: parsedData
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
private extension MQTTManager {
    
    func parseHexInput(_ input: String) -> [UInt8]? {
        let cleaned = input.components(separatedBy: .whitespacesAndNewlines).joined()
        guard cleaned.count % 2 == 0 else { return nil }

        var result: [UInt8] = []
        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let hexPair = String(cleaned[index..<nextIndex])
            if let byte = UInt8(hexPair, radix: 16) {
                result.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return result
    }
    
    func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
