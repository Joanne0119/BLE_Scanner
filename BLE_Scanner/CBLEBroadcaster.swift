//
//  CBLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/07/02
//

import Foundation
import CoreBluetooth

class CBLEBroadcaster: NSObject, ObservableObject {
    private var peripheralManager: CBPeripheralManager!
//    private let mask: [UInt8] = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF]
    @Published var nameStr = "N/A"
    @Published var isAdvertising = false
    @Published var isRepeatAdv = false
    private var lastMask: [UInt8] = []
    private var lastID: [UInt8] = []
    private var lastCustomData: [UInt8] = []
    

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func startAdvertising(mask: [UInt8], id: [UInt8], customData: [UInt8]) {
        print("開始廣播成功")
        guard peripheralManager.state == .poweredOn else {
                print("Peripheral 尚未準備好，請稍後再試")
                return
            }
        
        let payload: [UInt8] = mask + customData + id  // 中間加自定資料
        if payload.count > 26 {
            print("廣播資料超過限制：\(payload.count) bytes（最多 26）")
            return
        }
        nameStr = payload.map { String(format: "%02X", $0) }.joined()
        print(nameStr)
        let nameASCII = hexBytesToASCIIString(payload)
        print(nameASCII)

        let advData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: nameASCII
        ]
        
        print("Advertising Data: \(advData)")
        
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising(advData)
        
        self.isAdvertising = true
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        self.isAdvertising = false
    }
    
    func startRepeatingAdvertising(mask: [UInt8], id: [UInt8], customData: [UInt8], interval: TimeInterval = 30.0) {
        isRepeatAdv = true
        lastMask = mask
        lastID = id
        lastCustomData = customData

        advertiseCycle(interval: interval)
    }
    
    func stopRepeatingAdvertising() {
        isRepeatAdv = false
        stopAdvertising()
    }
    
    private func advertiseCycle(interval: TimeInterval) {
        if !isRepeatAdv { return }

        startAdvertising(mask: lastMask, id: lastID, customData: lastCustomData)
        print("Repeat Advertising...")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            self.stopAdvertising()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // 停止後等 1 秒再啟動（可調整）
                self.advertiseCycle(interval: interval)
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
    
    func hexBytesToASCIIString(_ bytes: [UInt8]) -> String {
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
    
    func isAsciiSafe(_ data: [UInt8]) -> Bool {
        for byte in data {
            if byte > 0x7F {
                return false
            }
        }
        return true
    }
    
}

extension CBLEBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("Peripheral 狀態：\(peripheral.state.rawValue)")
    }
}
