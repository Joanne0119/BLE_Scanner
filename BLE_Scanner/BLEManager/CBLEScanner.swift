//
//  CBLEScanner.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12
//  最後更新 2025/07/23
//

import Foundation
import CoreBluetooth

class CBLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var allPackets: [String: BLEPacket] = [:]
    @Published var matchedPackets: [String: BLEPacket] = [:]
    @Published var expectedMaskText: String = ""
    @Published var expectedIDText: String = ""
    @Published var expectedRSSI: Double = 0
    @Published var noMatchFound = false
    @Published var isScanning = false
    @Published var shouldStopScan = false
    @Published var testMethod:String = "default"
    @Published var averagedResults: [String: (tx: Double, rx: Double)] = [:]
    private var lastUpdateTimes: [String: Date] = [:]
    private var matchedCount = 0
    private var scanTimeoutTask: DispatchWorkItem?
    private let dataParser = BLEDataParser()
    private let dataProfile = ProfileDataGenerator()
    private var cleanupTimer: Timer?
    static let standardDataMask: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
    static let profileDataMask: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    private var averagingTimer: Timer?
    var averagingPacketID: String? // 追蹤正在計算哪個 packet
    private var rssiCaptures: [(tx: Int, rx: Int8)] = []
    
    
    override init() {
        super.init()
        let backgroundQueue = DispatchQueue(label: "tw.com.yourcompany.ble-scanner", qos: .background)
        centralManager = CBCentralManager(delegate: self, queue: backgroundQueue)
    }
    
    func startScanning() {
        allPackets.removeAll()
        //        matchedPackets.removeAll()
        matchedCount = 0
        noMatchFound = false
        centralManager.stopScan()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(withServices: nil, options:[
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
                print("開始掃描中...")
                
                self.setupCleanupTimer()
                
                // 開始倒數幾秒後檢查是否有匹配
                self.scanTimeoutTask?.cancel()
                self.scanTimeoutTask = DispatchWorkItem {
                    if self.matchedCount == 0 {
                        print("找不到符合條件的裝置，停止掃描。")
                        self.stopScanning()
                        
                        DispatchQueue.main.async {
                            self.noMatchFound = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.noMatchFound = false
                        }
                    }
                }
                if let task = self.scanTimeoutTask {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
                }
            }
        }
        isScanning = true
    }
    
    func stopScanning() {
        centralManager.stopScan()
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        isScanning = false
        print("停止掃描")
    }
    
    private func setupCleanupTimer() {
        // 先停止任何已存在的計時器，以防萬一
        cleanupTimer?.invalidate()
        
        // 建立一個新的計時器，每 2 秒執行一次 checkStaleDevices 方法
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkStaleDevices()
        }
    }
    
    private func checkStaleDevices() {
        let now = Date()
        let signalLostThreshold: TimeInterval = 5.0  // 5 秒沒收到信號 -> 標記為失聯 (變灰色)
        
        DispatchQueue.main.async {
            // 遍歷所有已匹配的裝置
            for (deviceID, packet) in self.matchedPackets {
                // 只檢查那些還沒被標記為失聯的裝置
                if !packet.hasLostSignal {
                    let timeSinceLastSeen = now.timeIntervalSince(packet.timestamp)
                    
                    if timeSinceLastSeen > signalLostThreshold {
                        print("裝置 \(packet.deviceID) 已失聯，更新其狀態。")
                        // 更新狀態，UI 會自動變為灰色
                        self.matchedPackets[deviceID]?.hasLostSignal = true
                        self.matchedPackets[deviceID]?.rssi = -199
                    }
                }
            }
        }
    }
    
    func startAveragingRSSI(for packetID: String, deviceID: String, completion: @escaping (Double, Double) -> Void) {
        
        averagingTimer?.invalidate()
        
        self.averagingPacketID = packetID
        
        var capturedTxs: [Int] = []
        var capturedRxs: [Int8] = []
        

        let startTime = Date()
        self.averagingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // 從 matchedPackets 取得最新的即時數值
            if let currentPacket = self.matchedPackets[deviceID],
               let profileData = currentPacket.profileData {
                
                capturedTxs.append(currentPacket.rssi)
                capturedRxs.append(profileData.phone_rssi)
            }
            
            if Date().timeIntervalSince(startTime) >= 10.0 {
                timer.invalidate() // 停止計時器

                let avgTx = capturedTxs.isEmpty ? 0.0 : Double(capturedTxs.reduce(0, +)) / Double(capturedTxs.count)
                let avgRx = capturedRxs.isEmpty ? 0.0 : Double(capturedRxs.reduce(0) { $0 + Int($1) }) / Double(capturedRxs.count)
                
                self.averagingPacketID = nil
                
                DispatchQueue.main.async {
                    completion(avgTx, avgRx)
                }
            }
        }
    }
    
    /// 停止計算流程
    func stopAveraging() {
        averagingTimer?.invalidate()
        averagingTimer = nil
        averagingPacketID = nil
        rssiCaptures.removeAll()
        print("RSSI 平均值計算已停止。")
    }
    
    // --- 新增私有方法，處理計時器邏輯 ---
    
    private func captureAndContinue(for deviceID: String) {
        guard averagingPacketID != nil else {
            stopAveraging()
            return
        }
        
        // 從 matchedPackets 中獲取最新的即時數據
        if let livePacket = self.matchedPackets[deviceID] {
            let tx = livePacket.rssi
            let rx = livePacket.profileData?.phone_rssi ?? 0
            rssiCaptures.append((tx: tx, rx: rx))
            print("第 \(rssiCaptures.count) 次數據抓取: TX=\(tx), RX=\(rx)")
        } else {
            // 如果剛好沒收到，就補 0
            rssiCaptures.append((tx: 0, rx: 0))
            print("第 \(rssiCaptures.count) 次數據抓取: 找不到裝置，數據為 0")
        }
        
        // 如果已抓取 3 次數據，就結束並計算平均值
        if rssiCaptures.count >= 3 {
            calculateAndStoreAverage()
        }
    }
    
    private func calculateAndStoreAverage() {
        guard let packetID = self.averagingPacketID, !rssiCaptures.isEmpty else {
            stopAveraging()
            return
        }
        
        print("抓取滿 3 次，開始計算平均值...")
        
        let totalTx = rssiCaptures.reduce(0) { $0 + $1.tx }
        let totalRx = rssiCaptures.reduce(0) { Int($0) + Int($1.rx) }
        
        let avgTx = Double(totalTx) / Double(rssiCaptures.count)
        let avgRx = Double(totalRx) / Double(rssiCaptures.count)
        
        // 將結果儲存在 @Published 字典中，UI 會自動收到通知
        DispatchQueue.main.async {
            self.averagedResults[packetID] = (tx: avgTx, rx: avgRx)
            print("計算完成 -> Packet ID: \(packetID), Avg TX: \(avgTx), Avg RX: \(avgRx)")
            self.stopAveraging() // 停止計時器和流程
        }
    }
    
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            //            print("centralManager: \(central.state.rawValue)");
            //            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let identifier = peripheral.identifier.uuidString
        let deviceName = peripheral.name ?? "Unknown"
        let rssiValue = RSSI.intValue
        let now = Date()
        if let lastUpdate = lastUpdateTimes[identifier],
           now.timeIntervalSince(lastUpdate) < 1.0 {
            // 如果距離上次更新不到 1 秒，就不處理
            return
        }
        lastUpdateTimes[identifier] = now
        
        
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if manufacturerData.count >= 29 {
                print("收到製造商數據：\(manufacturerData)")
                print("full packet: ")
                let manufacturerBytes = Array(manufacturerData)
                
                var deviceId = ""
                let rawDataStr = bytesToHexString(manufacturerBytes)
                var maskStr = ""
                var dataStr = ""
                var isMatched = false
                var parsedData: ParsedBLEData? = nil
                var profileData: ProfileData? = nil
                
                print(rawDataStr)
                
                let profileMaskLength = CBLEScanner.profileDataMask.count
                if manufacturerBytes.count >= profileMaskLength {
                    let receivedMask = Array(manufacturerBytes.prefix(profileMaskLength))
                    print("Thought is Profile Mode")
                    print(receivedMask)
                    
                    // Profile Mode
                    if receivedMask == CBLEScanner.profileDataMask {
                        isMatched = true
                        matchedCount += 1
                        print("Match Profile Packet")
                        
                        _ = 1
                        let idLength = 1
                        
                        let dataRange = profileMaskLength..<(manufacturerBytes.count - idLength)
                        let dataBytes = Array(manufacturerBytes[dataRange])
                        let idBytes = Array(manufacturerBytes.suffix(idLength))
                        
                        dataStr = bytesToHexString(dataBytes)
                        maskStr = bytesToHexString(receivedMask)
                        deviceId = idBytes.map { String($0) }.joined()
                        
                        let currentTestMethod = testMethod
                        if let result = dataProfile.parseDataBytes(dataBytes) {
                            profileData = result
                            profileData?.testMethod = currentTestMethod
                        }
                    }
                }
                
                
                if !isMatched {
                    let standardMaskLength = CBLEScanner.standardDataMask.count
                    if manufacturerBytes.count >= standardMaskLength {
                        let receivedMask = Array(manufacturerBytes.prefix(standardMaskLength))
                        print("Thought is Neighbor Mode")
                        print(receivedMask)
                        // Neighbor mode
                        if receivedMask == CBLEScanner.standardDataMask {
                            let standardDataLength = 15
                            let idLength = 1
                            let requiredTotalLength = standardMaskLength + standardDataLength + idLength
                            
                            if manufacturerBytes.count >= requiredTotalLength {
                                isMatched = true
                                matchedCount += 1
                                print("Match Neighbor Packet")
                                
                                // 根據 [Mask][Data][ID] 結構解析
                                let dataRange = standardMaskLength..<(manufacturerBytes.count - idLength)
                                let dataBytes = Array(manufacturerBytes[dataRange])
                                let idBytes = Array(manufacturerBytes.suffix(idLength))
                                
                                dataStr = bytesToHexString(dataBytes)
                                maskStr = bytesToHexString(receivedMask)
                                deviceId = idBytes.map { String($0) }.joined()
                                
                                if let result = dataParser.parseDataBytes(dataBytes) {
                                    parsedData = result
                                    print(dataParser.formatParseResult(result))
                                }
                            } else {
                                print("標準數據封包長度不足，期望至少 \(requiredTotalLength) bytes，實際: \(manufacturerBytes.count)")
                            }
                        }
                    }
                    
                    
                    
                }
                
                DispatchQueue.main.async {
                    var newReceptionCount = 1
                    if let existingPacket = self.allPackets[identifier] {
                        newReceptionCount = existingPacket.receptionCount + 1
                    }
                    
                    let generalPacket = BLEPacket(deviceID: deviceId,
                                                  identifier: identifier,
                                                  deviceName: deviceName,
                                                  rssi: rssiValue,
                                                  rawData: rawDataStr,
                                                  mask: maskStr,
                                                  data: dataStr,
                                                  isMatched: isMatched,
                                                  timestamp: now,
                                                  parsedData: parsedData,
                                                  profileData: profileData,
                                                  hasLostSignal: false,
                                                  testGroupID: TestSessionManager.shared.getCurrentTestID(),
                                                  receptionCount: newReceptionCount
                    )
                    self.allPackets[identifier] = generalPacket
                    
                    if isMatched {
                        var newMatchedCount = 1
                        if let existingMatchedPacket = self.matchedPackets[deviceId] {
                            newMatchedCount = existingMatchedPacket.receptionCount + 1
                        }
                        
                        var matchedPacket = generalPacket
                        matchedPacket.receptionCount = newMatchedCount
                        self.matchedPackets[deviceId] = matchedPacket
                    }
                    
                }
                func parseHexInput(_ input: String) -> [UInt8]? {
                    let cleaned = input.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined()
                    guard cleaned.count % 2 == 0 else { return nil }  // 字數必須是偶數，否則不是合法的 hex byte 序列
                    
                    var result: [UInt8] = []
                    var index = cleaned.startIndex
                    
                    while index < cleaned.endIndex {
                        let nextIndex = cleaned.index(index, offsetBy: 2)
                        let hexPair = String(cleaned[index..<nextIndex])
                        if let byte = UInt8(hexPair, radix: 16) {
                            result.append(byte)
                        } else {
                            return nil  // 只要其中一組轉換失敗就整體失敗
                        }
                        index = nextIndex
                    }
                    return result
                }
                
                func asciiStringToBytes(_ input: String) -> [UInt8] {
                    print("asciiStringToBytes Input: \(input)")
                    return Array(input.utf8)
                }
                
                func bytesToHexString(_ bytes: [UInt8]) -> String {
                    print("bytesToHexString Input: \(bytes)")
                    return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                }
                
                
            }
        }
    }
}
extension String {
    func chunks(of length: Int) -> [String] {
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: length, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result
    }
}
