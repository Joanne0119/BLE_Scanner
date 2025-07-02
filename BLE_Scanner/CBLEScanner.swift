//
//  CBLEScanner.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12
//  最後更新 2025/07/02
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
    private var lastUpdateTimes: [String: Date] = [:]
    private var matchedCount = 0
    private var scanTimeoutTask: DispatchWorkItem?
    private let dataParser = BLEDataParser()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        allPackets.removeAll()
        matchedPackets.removeAll()
        matchedCount = 0
        noMatchFound = false
        centralManager.stopScan()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(withServices: nil, options:[
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
                print("開始掃描中...")

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
        isScanning = false
        print("停止掃描")
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
        var deviceName = peripheral.name ?? "Unknown"
        let rssiValue = RSSI.intValue
        var deviceId = ""

        var isMatched = false
        var rawDataStr = ""
        var maskStr = ""
        var dataStr = ""
        let now = Date()
        var parsedData: ParsedBLEData? = nil
        if let lastUpdate = lastUpdateTimes[identifier],
           now.timeIntervalSince(lastUpdate) < 1.0 {
            // 如果距離上次更新不到 1 秒，就不處理
            return
        }
        lastUpdateTimes[identifier] = now
        
//        print("發現裝置：\(deviceName), RSSI: \(rssiValue)")
//        print("廣播封包內容：")
//        for (key, value) in advertisementData {
//            print("\(key): \(value)")
//        }
//        print(allPackets)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("收到製造商數據：\(manufacturerData)")
            print("full packet: ")
            let manufacturerBytes = Array(manufacturerData)
            rawDataStr = bytesToHexString(manufacturerBytes)
            print(rawDataStr);
           
            let idLength = 1
            let deviceIdBytes = Array(manufacturerBytes.suffix(idLength))
            print("id: ")
            deviceId = deviceIdBytes.map { String($0) }.joined(separator: " ")
            // 解析expectedMask和expectedID
            let expectedMask = parseHexInput(expectedMaskText)
            let maskLength = expectedMask?.count ?? 14
            if manufacturerBytes.count >= (maskLength) + (idLength) {
                let receivedMask = Array(manufacturerBytes.prefix(maskLength))
                let receivedID = deviceIdBytes
                let dataRange = maskLength..<(manufacturerBytes.count - idLength)
                let dataBytes = Array(manufacturerBytes[dataRange])
                
                
                maskStr = bytesToHexString(receivedMask)
                dataStr = bytesToHexString(dataBytes)
                
                let expectedID: [UInt8]? = expectedIDText.isEmpty ? nil : parseHexInput(expectedIDText)
                
                print("expectedMaskText \(expectedMaskText), expectedIDText \(expectedIDText)")
                print("expectedMask \(String(describing: expectedMask)), expectedID \(String(describing: expectedID))")
                print("receivedMask \(receivedMask), receivedID \(receivedID), dataStr \(dataStr)")
                
                if receivedMask == expectedMask && (expectedID == nil || receivedID == expectedID!) {
                    isMatched = true
                    
                    
                    // 解析數據
                    if let result = dataParser.parseDataString(dataStr) {
                        parsedData = result  // 直接賦值給變數
                        print(dataParser.formatParseResult(result))
                        
                        // 檢查是否需要停止掃描
//                        if result.hasReachedTarget && shouldStopScan {
//                            print("檢測到裝置接收次數達到100次，停止掃描")
//                            stopScanning()
//                        }
                        
                    }
                    
                    matchedCount += 1
                    print("Is Match！")
                   
                }
            }
            
            
            
        }

        DispatchQueue.main.async {
            let packet = BLEPacket(deviceID: deviceId,
                                   identifier: identifier,
                                   deviceName: deviceName,
                                   rssi: rssiValue,
                                   rawData: rawDataStr,
                                   mask: maskStr,
                                   data: dataStr,
                                   isMatched: isMatched,
                                   timestamp: now,
                                   parsedData: parsedData
                                )
            self.allPackets[identifier] = packet
            
            if isMatched {
                self.matchedPackets[deviceId] = packet
            }
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
