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
    private let mask: [UInt8] = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF]
    @Published var nameStr = "N/A"

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func startAdvertising(id: UInt8, customData: [UInt8]) {
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.peripheralManager.stopAdvertising()
            print("廣播已自動停止")
        }
    }
    
    func parseHexInput(_ input: String) -> [UInt8]? {
            let parts = input.split(separator: " ")
            var result: [UInt8] = []
            for part in parts {
                if let byte = UInt8(part, radix: 16) {
                    result.append(byte)
                } else {
                    return nil
                }
            }
            return result
        }
}

extension CBLEBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("Peripheral 狀態：\(peripheral.state.rawValue)")
    }
}
