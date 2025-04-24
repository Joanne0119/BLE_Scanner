//
//  CBLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//

import Foundation
import CoreBluetooth

class CBLEBroadcaster: NSObject, ObservableObject {
    private var peripheralManager: CBPeripheralManager!
//    private let mask: [UInt8] = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF]
    @Published var nameStr = "N/A"

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func startAdvertising(mask: [UInt8], id: UInt8, customData: [UInt8]) {
        print("開始廣播成功")
        guard peripheralManager.state == .poweredOn else {
                print("Peripheral 尚未準備好，請稍後再試")
                return
            }
        
        let payload: [UInt8] = mask + customData + [id]  // 中間加自定資料
        if payload.count > 29 {
            print("廣播資料超過限制：\(payload.count) bytes（最多 29）")
            return
        }
        let nameStr = payload.map { String(format: "%02X", $0) }.joined()
        
//        let data = Data(payload)
//        currentPayload = payload.map { String(format: "%02X", $0) }.joined(separator: " ")

        let advData: [String: Any] = [
//            CBAdvertisementDataManufacturerDataKey: data,
            CBAdvertisementDataLocalNameKey: nameStr
        ]
        
        print("Advertising Data: \(advData)")
        
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising(advData)
        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
//            self.peripheralManager.stopAdvertising()
//            print("廣播已自動停止")
//        }
    }
    
    var isAdvertising: Bool {
        return peripheralManager.isAdvertising
    }
    
    func stopAdervtising() {
        peripheralManager.stopAdvertising()
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

extension CBLEBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("Peripheral 狀態：\(peripheral.state.rawValue)")
    }
}
