//
//  CBLEScanner.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12
//

import Foundation
import CoreBluetooth

class CBLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var allPackets: [String: BLEPacket] = [:]
    @Published var expectedMaskText: String = ""
    @Published var expectedIDText: String = ""
    @Published var noMatchFound = false
    private var matchedCount = 0
    private var scanTimeoutTask: DispatchWorkItem?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        allPackets.removeAll()
        matchedCount = 0
        noMatchFound = false
        centralManager.stopScan()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(withServices: nil, options: nil)
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
    }
    
    func stopScanning() {
        centralManager.stopScan()
        allPackets.removeAll()
    }


    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("centralManager: \(central.state.rawValue)");
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let identifier = peripheral.identifier.uuidString
        var deviceName = peripheral.name ?? "Unknown"
        let rssiValue = RSSI.intValue

        var isMatched = false
        var rawDataStr = ""
        
//        print("發現裝置：\(deviceName), RSSI: \(rssiValue)")
//            print("廣播封包內容：")
//            for (key, value) in advertisementData {
//                print("\(key): \(value)")
//            }
//        print(allPackets)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("收到裝置名稱：\(localName)")
            rawDataStr = localName
            deviceName = localName
            // 解析expectedMask和expectedID
            let expectedMask = parseHexInput(expectedMaskText)
            let expectedID: UInt8? = expectedIDText.isEmpty ? nil : UInt8(expectedIDText, radix: 16)
            
//            var bytes: [UInt8] = []
//            var index = localName.startIndex
//            while index < localName.endIndex {
//                let nextIndex = localName.index(index, offsetBy: 2, limitedBy: localName.endIndex) ?? localName.endIndex
//                if nextIndex <= localName.endIndex {
//                    let hexStr = String(localName[index..<nextIndex])
//                    if let byte = UInt8(hexStr, radix: 16) {
//                        bytes.append(byte)
//                    }
//                }
//                index = nextIndex
//            }
//
//            let expectedMask = expectedMaskText.uppercased().chunks(of: 2).compactMap { UInt8($0, radix: 16) }
//            let expectedID = UInt8(expectedIDText.uppercased(), radix: 16)
//
//            if bytes.count >= expectedMask.count + 1 {
//                let mask = Array(bytes.prefix(expectedMask.count))
//                let id = bytes[expectedMask.count]
//                if mask == expectedMask && (expectedIDText.isEmpty || id == expectedID) {
//                    isMatched = true
//                    matchedCount += 1
//                }
//            }
            if let bytesFromName = parseHexInput(localName) {
                if bytesFromName.count >= (expectedMask?.count ?? 0) + 1 {
                    let receivedMask = Array(bytesFromName.prefix(expectedMask?.count ?? 0))
                    let receivedID = bytesFromName.count > (expectedMask?.count ?? 0) ? bytesFromName[expectedMask?.count ?? 0] : nil
                    print("in")
                    if receivedMask == expectedMask && (expectedID == nil || receivedID == expectedID) {
                        isMatched = true
                        matchedCount += 1
                        print("Is Match！")
                    }
                }
            }
            
            
        }

        DispatchQueue.main.async {
            let packet = BLEPacket(identifier: identifier,
                                   deviceName: deviceName,
                                   rssi: rssiValue,
                                   rawData: rawDataStr,
                                   isMatched: isMatched)
            self.allPackets[identifier] = packet
        }
        
        func parseHexInput(_ input: String) -> [UInt8]? {
            let cleaned = input.replacingOccurrences(of: " ", with: "")  // 如果有空格也先清掉
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
