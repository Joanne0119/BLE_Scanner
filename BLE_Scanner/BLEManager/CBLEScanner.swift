//
//  CBLEScanner.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12
//  最後更新 2025/07/23
//

import Foundation
import CoreBluetooth
import Combine

struct ProfileResult {
    let packetID: String
    let avgTx: Double
    let avgRx: Double
    let capturedTxs: [Int]
    let capturedRxs: [Int8]
}

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

   let profileResultPublisher = PassthroughSubject<ProfileResult, Never>()
   private var isAveragingInProgress = false
   var averagingPacketID: String?
   private var averagingTargetDeviceID: String?
   
   // --- 數據捕獲屬性 ---
   private var txCaptureSession: [Int] = []
   private var rxCaptureSession: [Int8] = []
    
    
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
    
    func startAveragingRSSI(for packetID: String, deviceID: String, completion: @escaping (Double, Double, [Int], [Int8]) -> Void) {
            // 如果已有任務在執行，先停止
            if isAveragingInProgress {
                stopAveraging()
            }
            
            print("開始為 Packet ID \(packetID) 捕獲數據...")
            
            // 設定狀態
            self.averagingPacketID = packetID
            self.isAveragingInProgress = true
            self.averagingTargetDeviceID = deviceID
            
            // 清空上次的數據
            self.txCaptureSession.removeAll()
            self.rxCaptureSession.removeAll()
        }
    
    // 停止
    func stopAveraging() {
        print("停止數據捕獲流程。")
        isAveragingInProgress = false
        averagingPacketID = nil
        averagingTargetDeviceID = nil
        txCaptureSession.removeAll()
        rxCaptureSession.removeAll()
    }
    
    // --- 新增私有方法，處理計時器邏輯 ---
    private func finishProfileCapture() {
        print("已成功捕獲 30 筆數據，正在計算與回傳結果...")
        
        guard let finishedPacketID = self.averagingPacketID else {
            stopAveraging()
            return
        }
        
        let avgTx = txCaptureSession.isEmpty ? 0.0 : Double(txCaptureSession.reduce(0, +)) / Double(txCaptureSession.count)
        let avgRx = rxCaptureSession.isEmpty ? 0.0 : Double(rxCaptureSession.reduce(0) { $0 + Int($1) }) / Double(rxCaptureSession.count)
        
        // 建立結果物件
        let result = ProfileResult(
            packetID: finishedPacketID,
            avgTx: avgTx,
            avgRx: avgRx,
            capturedTxs: self.txCaptureSession,
            capturedRxs: self.rxCaptureSession
        )
        
        DispatchQueue.main.async {
            self.profileResultPublisher.send(result)
        }
        
        stopAveraging()
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

        if let lastUpdate = lastUpdateTimes[identifier], now.timeIntervalSince(lastUpdate) < 0.3 {
            return
        }
        lastUpdateTimes[identifier] = now
        
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }

        // --- 在背景執行緒解析封包 ---
        let manufacturerBytes = Array(manufacturerData)
        var deviceId = ""
        var maskStr = ""
        var dataStr = ""
        var isMatched = false
        var parsedData: ParsedBLEData? = nil
        var profileData: ProfileData? = nil
        
        // 嘗試解析 Profile 封包
        let profileMaskLength = CBLEScanner.profileDataMask.count
        if manufacturerBytes.count >= profileMaskLength {
            let receivedMask = Array(manufacturerBytes.prefix(profileMaskLength))
            if receivedMask == CBLEScanner.profileDataMask {
                isMatched = true
                let idLength = 1
                let dataRange = profileMaskLength..<(manufacturerBytes.count - idLength)
                let dataBytes = Array(manufacturerBytes[dataRange])
                let idBytes = Array(manufacturerBytes.suffix(idLength))
                dataStr = bytesToHexString(dataBytes)
                maskStr = bytesToHexString(receivedMask)
                deviceId = idBytes.map { String($0) }.joined()
                
                if let result = dataProfile.parseDataBytes(dataBytes) {
                    profileData = result
                    profileData?.testMethod = self.testMethod // 使用 class 屬性
                }
            }
        }
        
        // 嘗試解析 Neighbor 封包
        if !isMatched {
            let standardMaskLength = CBLEScanner.standardDataMask.count
            if manufacturerBytes.count >= (standardMaskLength + 15 + 1) { // 確保長度足夠
                let receivedMask = Array(manufacturerBytes.prefix(standardMaskLength))
                if receivedMask == CBLEScanner.standardDataMask {
                    isMatched = true
                    let idLength = 1
                    let dataRange = standardMaskLength..<(manufacturerBytes.count - idLength)
                    let dataBytes = Array(manufacturerBytes[dataRange])
                    let idBytes = Array(manufacturerBytes.suffix(idLength))
                    dataStr = bytesToHexString(dataBytes)
                    maskStr = bytesToHexString(receivedMask)
                    deviceId = idBytes.map { String($0) }.joined()
                    parsedData = dataParser.parseDataBytes(dataBytes)
                }
            }
        }
        
        guard isMatched, !deviceId.isEmpty else { return }

        // --- 切換到主執行緒來更新 @Published 屬性並執行捕獲邏輯 ---
        DispatchQueue.main.async { [self] in
            self.matchedCount = isMatched ? self.matchedCount + 1 : self.matchedCount
            
            // 建立或更新 BLEPacket
            var packet = BLEPacket(
                deviceID: deviceId,
                identifier: identifier,
                deviceName: deviceName,
                rssi: rssiValue,
                rawData: self.bytesToHexString(manufacturerBytes),
                mask: maskStr, // 可以在解析時填充
                data: dataStr, // 可以在解析時填充
                isMatched: isMatched,
                timestamp: now,
                parsedData: parsedData,
                profileData: profileData,
                hasLostSignal: false,
                testGroupID: TestSessionManager.shared.getCurrentTestID(),
                receptionCount: (self.matchedPackets[deviceId]?.receptionCount ?? 0) + 1
            )
            
            self.allPackets[identifier] = packet
            self.matchedPackets[deviceId] = packet
            
            
            if self.isAveragingInProgress,
               let targetDeviceID = self.averagingTargetDeviceID,
               packet.deviceID == targetDeviceID,
               let currentProfileData = packet.profileData {
                
                if self.txCaptureSession.count < 30 {
                    self.txCaptureSession.append(packet.rssi)
                    self.rxCaptureSession.append(currentProfileData.phone_rssi)
                    
                    print("  捕獲第 \(self.txCaptureSession.count)/30 筆數據: TX=\(packet.rssi), RX=\(currentProfileData.phone_rssi)")
                    
                    if self.txCaptureSession.count == 30 {
                        self.finishProfileCapture()
                    }
                }
            }
        }
    }
    private func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
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
