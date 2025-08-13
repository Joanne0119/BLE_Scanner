//
//  ProflieData.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/8/8.
//

import SwiftUI
import Foundation
import Combine


struct ProfileData: Codable, Equatable {
    var phone_rssi: Int8
    var testMethod: String
    var avgTx: Double?
    var avgRx: Double?
}

class ProfileDataGenerator {
    func parseDataBytes(_ dataBytes: [UInt8]) -> ProfileData? {
        guard dataBytes.count == 1 else {
            print("Profile 數據長度錯誤，期望1 bytes，實際: \(dataBytes.count)")
            return nil
        }
        return parseProfileData(dataBytes)
    }
    
    func parseProfileData(_ dataBytes: [UInt8]) -> ProfileData? {
        return ProfileData(
            phone_rssi: Int8(bitPattern: dataBytes[0]),
            testMethod: ""
        )
        
    }
    
    private func parseHexInput(_ hexString: String) -> [UInt8]? {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: cleanHex.count, by: 2) {
            let startIndex = cleanHex.index(cleanHex.startIndex, offsetBy: i)
            let endIndex = cleanHex.index(startIndex, offsetBy: 2)
            let hexByte = String(cleanHex[startIndex..<endIndex])
            
            if let byte = UInt8(hexByte, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
        }
        return bytes
    }
}
