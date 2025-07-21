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
import Network


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
    private var isConnecting = false
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isInBackground = false
    private var isShuttingDown = false
    
    // MARK: - 離線緩衝相關
    @Published var pendingMessageCount: Int = 0 // 用於更新 UI
    private var messageBuffer: [PendingMessage] = []
    private let bufferFileName = "mqtt_message_buffer.json"
    
    // MARK: - 網路監控
    private var pathMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "network.monitor.queue")
    @Published var isNetworkAvailable: Bool = true
    private var isHandlingNetworkReconnect = false
    
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
        loadBufferFromFile()
        setupMQTT()
        setupNetworkMonitor()
        startConnectionMonitoring()
        setupBackgroundNotifications()
    }
    
    deinit {
        print("MQTTManager 正在釋放...")
        pathMonitor?.cancel()
        stopConnectionMonitoring()
        cleanupGracefully()
    }
    
    // MARK: - 背景模式處理
    private func setupBackgroundNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("App 進入背景模式")
        isInBackground = true
        
        // 開始背景任務
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        // 暫停連線監控
        stopConnectionMonitoring()
        
        // 保持連線但停止主動檢查
        print("背景模式：暫停連線監控")
    }
    
    @objc private func appWillEnterForeground() {
        print("App 即將進入前台")
        isInBackground = false
        
        // 結束背景任務
        endBackgroundTask()
        
        // 重新開始連線監控
        startConnectionMonitoring()
        
        // 檢查連線狀態
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkConnectionStatus()
        }
        
        print("前台模式：恢復連線監控")
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    // MARK: - 連接監控
    private func startConnectionMonitoring() {
        // 背景模式下不啟動監控
        guard !isInBackground else {
            print("背景模式下跳過連線監控")
            return
        }
        
        stopConnectionMonitoring()
        
        connectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: connectionCheckInterval, repeats: true) { [weak self] _ in
            // 再次檢查是否在背景模式
            guard let self = self, !self.isInBackground, !self.isShuttingDown else { return }
            self.checkConnectionStatus()
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
        guard !isInBackground, !isShuttingDown else { return }
        
        guard isNetworkAvailable else {
            if connectionStatus != "網路不可達" {
                DispatchQueue.main.async {
                    self.connectionStatus = "網路不可達"
                    self.isConnected = false
                }
            }
            return
        }
        
        guard let mqttClient = mqttClient else {
            handleConnectionLost()
            return
        }
        
        // 檢查網路可達性
        if !isNetworkReachable() {
            print("網路不可達，跳過連線檢查")
            DispatchQueue.main.async {
                self.connectionStatus = "網路不可達"
                self.isConnected = false
            }
            return
        }
        
        // 使用更可靠的連接檢查方法
        checkMQTTConnectionReliably(mqttClient)
    }
    
    private func checkMQTTConnectionReliably(_ mqttClient: MQTTClient) {
        // 嘗試訂閱一個測試主題來檢查連接
        let testSubscription = MQTTSubscribeInfo(topicFilter: "connection/test/\(clientID)", qos: .atMostOnce)
        
        mqttClient.subscribe(to: [testSubscription]).whenComplete { [weak self] result in
            guard let self = self, !self.isInBackground, !self.isShuttingDown else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if !self.isConnected {
                        print("連接狀態檢查：連接正常")
                        self.isConnected = true
                        self.connectionStatus = "已連接"
                        self.reconnectAttempts = 0
                    }
                    
                    // 取消訂閱測試主題
                    mqttClient.unsubscribe(from: ["connection/test/\(self.clientID)"]).whenComplete { _ in }
                    
                case .failure(let error):
                    print("連接檢查失敗: \(error)")
                    self.handleConnectionLost()
                }
            }
        }
    }
    
    private func isNetworkReachable() -> Bool {
        return self.isNetworkAvailable 
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
        print("isShuttingDown：\(isShuttingDown) isReconnecting : \(isReconnecting)")
        guard !isInBackground, !isShuttingDown, !isReconnecting else { return }
        
        isReconnecting = true
        reconnectAttempts += 1
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "重連中... (第 \(self.reconnectAttempts) 次)"
        }
        
        print("開始重連流程，第 \(reconnectAttempts) 次嘗試")
        
        if reconnectAttempts > maxReconnectAttempts {
            isReconnecting = false
            isHandlingNetworkReconnect = false
            DispatchQueue.main.async {
                self.connectionStatus = "重連失敗，已停止嘗試"
            }
            print("重連次數超過限制，停止重連")
            return
        }
        
        // 先確實斷開現有連接
        if let mqttClient = mqttClient {
            mqttClient.disconnect().whenComplete { [weak self] _ in
                // 等待斷開完成後再重連
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.performReconnect()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + reconnectInterval) {
                self.performReconnect()
            }
        }
    }
    
    private func performReconnect() {
        guard !isInBackground, !isShuttingDown else {
            isReconnecting = false
            return
        }
        
        print("執行重連...")
        
        // 重新初始化MQTT
        setupMQTT()
        
        // 等待初始化完成後再連接
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard !self.isInBackground, !self.isShuttingDown else {
                self.isReconnecting = false
                return
            }
            
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
    
    private func setupNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            print("網路狀態變更處理程序已觸發！狀態: \(path.status)")
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    print("網路已連線")
                    self?.isNetworkAvailable = true
                    self?.connectionStatus = "網路已連線"
                    
                    // 如果網路剛恢復，且 MQTT 未連線，則主動觸發一次連線
                    if self?.isConnected == false && self?.isHandlingNetworkReconnect == false {
                        self?.isHandlingNetworkReconnect = true
                        print("網路已恢復，且無重連任務進行中，觸發一次強制重連。")
                        self?.forceReconnect()
                    }
                    
                } else {
                    print("網路已中斷")
                    self?.isNetworkAvailable = false
                    self?.isConnected = false // 網路中斷，MQTT 必然中斷
                    self?.connectionStatus = "網路不可達"
                }
            }
        }
        
        pathMonitor?.start(queue: networkMonitorQueue)
    }
    
    private func setupMQTT() {
        mqttQueue.async { [weak self] in
            self?.performSetupMQTT()
        }
    }
    
    private func performSetupMQTT() {
        // 此函式在序列佇列 mqttQueue 中執行，確保操作的原子性。
        
        // 1. 正確且安全地關閉舊的 Client
        //    對於使用 .createNew 建立的 client，必須呼叫 syncShutdownGracefully()。
        if let oldClient = self.mqttClient {
            do {
                print("正在從 performSetupMQTT 安全關閉舊的 MQTT Client...")
                try oldClient.syncShutdownGracefully()
                print("舊的 MQTT Client 已成功關閉。")
            } catch {
                print("從 performSetupMQTT 關閉舊的 MQTT Client 時發生錯誤: \(error)")
            }
        }
        
        // 舊的 client 已完全關閉，現在可以安全地將其設為 nil。
        self.mqttClient = nil
        // 由於我們不再手動管理 eventLoopGroup，也將其設為 nil 以保持一致。
        self.eventLoopGroup = nil

        // 2. 建立新的資源 (與上次修改相同)
        print("開始建立新的 MQTT 資源...")
        
        let configuration = MQTTClient.Configuration(
            keepAliveInterval: .seconds(30),
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
        
        print("新的 MQTT 客戶端初始化成功")
        
        DispatchQueue.main.async {
            self.connectionStatus = "已初始化"
        }
    }
    
    
    private func cleanupGracefully() {
        // 這個函式只在 deinit 時被呼叫，負責最終的、一次性的清理。
        isShuttingDown = true
        
        // 停止所有 Timer
        stopConnectionMonitoring()
        
        // 正確且安全地關閉 Client
        if let client = self.mqttClient {
            do {
                print("正在從 deinit 安全關閉 MQTT Client...")
                // 使用 syncShutdownGracefully 來確保 client 的 EventLoopGroup 被關閉。
                try client.syncShutdownGracefully()
                print("MQTT Client 已從 deinit 安全關閉。")
            } catch {
                print("從 deinit 關閉 MQTT Client 時發生錯誤: \(error)")
            }
        }
        
        self.mqttClient = nil
        self.eventLoopGroup = nil
    }
    
//    private func finalizeCleanup() {
//        mqttClient = nil
//        
//        // 更安全地關閉 EventLoopGroup
//        if let eventLoopGroup = eventLoopGroup {
//            let group = eventLoopGroup
//            self.eventLoopGroup = nil
//            
//            DispatchQueue.global(qos: .background).async {
//                do {
//                    try group.syncShutdownGracefully()
//                    print("EventLoopGroup 已安全關閉")
//                } catch {
//                    print("EventLoopGroup 關閉時發生錯誤: \(error)")
//                }
//            }
//        }
//    }
    
    // MARK: - 連接管理
    func connect() {
        guard !isConnected && !isConnecting else {
            print("已在連線中或已連線，跳過此次 connect() 請求。")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performConnect()
        }
    }
    
    private func performConnect() {
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
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
            self.isConnected = false // 確保連接狀態為 false
        }
        
        mqttClient.connect().whenComplete { [weak self] result in
            guard let self = self else { return }
            self.isConnecting = false
            
            switch result {
            case .success:
                print("MQTT 連接成功，等待連接穩定...")
                
                // 不要立即設置 isConnected = true
                DispatchQueue.main.async {
                    self.connectionStatus = "連接成功，正在初始化..."
                }
                
                // 延遲一下再設置監聽器和訂閱
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    self.setupListenersAndSubscribe()
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.connectionStatus = "連接失敗: \(error.localizedDescription)"
                }
                print("MQTT 連接失敗: \(error)")
                self.startReconnectProcess()
            }
        }
    }
    
    private func setupListenersAndSubscribe() {
        guard let mqttClient = mqttClient else { return }
        
        // 設置訊息監聽器
        mqttClient.addPublishListener(named: "MessageHandler") { [weak self] result in
            switch result {
            case .success(let publishInfo):
                self?.enhancedHandleReceivedMessage(publishInfo)
            case .failure(let error):
                print("收到訊息時發生錯誤: \(error)")
            }
        }
        
        // 設置連接關閉監聽器
        mqttClient.addCloseListener(named: "ConnectionMonitor") { [weak self] result in
            print("MQTT 連接已關閉")
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.connectionStatus = "連接中斷"
            }
            self?.startReconnectProcess()
        }
        
        // 開始訂閱
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
        guard let mqttClient = mqttClient else { return }
        
        DispatchQueue.main.async {
            self.connectionStatus = "正在訂閱主題..."
        }
        
        let subscriptions = [
            // 壓力校正主題
            MQTTSubscribeInfo(topicFilter: pressureDownloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(pressureRequestTopic)/response", qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: pressureDeleteTopic, qos: .atLeastOnce),
            // 掃描 Log 主題
            MQTTSubscribeInfo(topicFilter: logDownloadTopic, qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "\(logRequestTopic)/response", qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: logDeleteTopic, qos: .atLeastOnce),
            // Suggestion 主題
            MQTTSubscribeInfo(topicFilter: "suggestion/+/download", qos: .atLeastOnce)
        ]
        
        mqttClient.subscribe(to: subscriptions).whenComplete { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let subAckReturnCodes):
                    print("訂閱成功，返回碼: \(subAckReturnCodes)")
                    // 只有在訂閱成功後才設置為已連接
                    self?.isConnected = true
                    self?.connectionStatus = "已連接"
                    self?.reconnectAttempts = 0
                    
                    self?.isHandlingNetworkReconnect = false
                    
                    // 清空緩衝
                    self?.flushBuffer()
                    
                    // 訂閱成功後請求初始資料
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                        self?.requestAllInitialData()
                    }
                    
                case .failure(let error):
                    print("訂閱失敗: \(error)")
                    self?.isConnected = false
                    self?.connectionStatus = "訂閱失敗: \(error.localizedDescription)"
                    // 訂閱失敗時重新連接
                    self?.startReconnectProcess()
                }
            }
        }
        
        printSubscribedTopics()
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
        // 檢查連接狀態
        guard isConnected else {
            print("MQTT 未連線，訊息將存入緩衝區。主題: \(topic)")
            // 建立待發送訊息物件
            let pendingMessage = PendingMessage(topic: topic, payload: payload, timestamp: Date())
            // 加入到緩衝區並儲存
            messageBuffer.append(pendingMessage)
            saveBufferToFile()
            return
        }
        
        performPublish(topic: topic, payload: payload)
    }
    
    private func performPublish(topic: String, payload: String) {
        guard let mqttClient = mqttClient else {
            print("MQTT 客戶端未初始化，無法發送訊息到主題: \(topic)")
            return
        }
        
        let buffer = ByteBuffer(string: payload)
        mqttClient.publish(to: topic, payload: buffer, qos: .atLeastOnce).whenComplete { [weak self] result in
            switch result {
            case .success:
                print("訊息發送成功 -> 主題: \(topic)")
            case .failure(let error):
                print("訊息發送失敗 -> 主題: \(topic), 錯誤: \(error)")
                // 這裡可以考慮是否要將發送失敗的訊息再次加回緩衝區
                if error.localizedDescription.contains("noConnection") {
                    self?.handleConnectionLost()
                }
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
        
        if mqttClient != nil {
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
// MARK: - 緩衝儲存
private extension MQTTManager {
    
    // 取得緩衝檔案的完整路徑
    var bufferFileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(bufferFileName)
    }
    
    // 將當前的 messageBuffer 儲存到檔案
    func saveBufferToFile() {
        mqttQueue.async {
            do {
                let data = try JSONEncoder().encode(self.messageBuffer)
                try data.write(to: self.bufferFileURL, options: .atomic)
                DispatchQueue.main.async {
                    self.pendingMessageCount = self.messageBuffer.count
                }
                print("緩衝區已儲存，共 \(self.messageBuffer.count) 筆訊息。")
            } catch {
                print("儲存緩衝區失敗: \(error)")
            }
        }
    }
    
    // 從檔案載入緩衝區到 messageBuffer
    func loadBufferFromFile() {
        mqttQueue.async {
            guard FileManager.default.fileExists(atPath: self.bufferFileURL.path) else {
                print("找不到緩衝檔案，無需載入。")
                return
            }
            
            do {
                let data = try Data(contentsOf: self.bufferFileURL)
                self.messageBuffer = try JSONDecoder().decode([PendingMessage].self, from: data)
                DispatchQueue.main.async {
                    self.pendingMessageCount = self.messageBuffer.count
                }
                print("緩衝區已從檔案載入，共 \(self.messageBuffer.count) 筆訊息。")
            } catch {
                print("載入緩衝區失敗: \(error)")
                // 如果解碼失敗，可能檔案已損毀，清空以防萬一
                self.messageBuffer = []
            }
        }
    }
    
    func flushBuffer() {
        mqttQueue.async {
            // 將緩衝區複製一份到本地變數，並清空類別屬性
            let messagesToFlush = self.messageBuffer
            self.messageBuffer.removeAll()
            
            // 如果沒有訊息需要發送，則直接更新檔案並返回
            guard !messagesToFlush.isEmpty else {
                self.saveBufferToFile() // 確保檔案也被清空
                return
            }
            
            print("準備發送 \(messagesToFlush.count) 筆緩衝訊息...")
            
            // 依序發送所有訊息
            for message in messagesToFlush {
                // 稍作延遲，避免瞬間發送大量訊息給 Broker 造成壓力
                Thread.sleep(forTimeInterval: 0.1)
                self.performPublish(topic: message.topic, payload: message.payload)
            }
            
            // 發送完畢後，再次儲存（此時 messageBuffer 應為空）
            self.saveBufferToFile()
        }
    }
}
