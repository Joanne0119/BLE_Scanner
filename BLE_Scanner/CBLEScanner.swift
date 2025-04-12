//
//  CBLEScanner.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/11.
//

import Foundation
import CoreBluetooth

class CBLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var allPackets: [String: BLEPacket] = [:]
    let expectedMask: [UInt8] = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        allPackets.removeAll()
        centralManager.stopScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(withServices: nil, options: nil)
            }
        }
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
        let deviceName = peripheral.name ?? "Unknown"
        let rssiValue = RSSI.intValue

        var isMatched = false
        var rawDataStr = ""
        
        print("發現裝置：\(deviceName), RSSI: \(rssiValue)")
            print("廣播封包內容：")
            for (key, value) in advertisementData {
                print("\(key): \(value)")
            }
        print(allPackets)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("收到裝置名稱：\(localName)")
            rawDataStr = localName
            var bytes: [UInt8] = []
            var index = localName.startIndex
            while index < localName.endIndex {
                let nextIndex = localName.index(index, offsetBy: 2)
                if nextIndex <= localName.endIndex {
                    let hexStr = String(localName[index..<nextIndex])
                    if let byte = UInt8(hexStr, radix: 16) {
                        bytes.append(byte)
                    }
                }
                index = localName.index(index, offsetBy: 2)
            }

            if bytes.count >= 7 {
                let mask = Array(bytes.prefix(6))
                let id = bytes[6]
                if mask == expectedMask {
                    isMatched = true
                    print("成功配對，ID: \(id)")
                }
            }
            
            
        }
           
//        if let mData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
//            print("有收到 Manufacturer Data")
//            let bytes = [UInt8](mData)
//            rawDataStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
//
//            if bytes.count >= 7 {
//                let mask = Array(bytes.prefix(6))
//                _ = bytes.last ?? 0
//                if mask == expectedMask {
//                    isMatched = true
//                }
//            }
//        }
//        else {
//            print("沒有收到 Manufacturer Data")
//        }

        DispatchQueue.main.async {
            let packet = BLEPacket(identifier: identifier,
                                   deviceName: deviceName,
                                   rssi: rssiValue,
                                   rawData: rawDataStr,
                                   isMatched: isMatched)
            self.allPackets[identifier] = packet
        }

    }
}
