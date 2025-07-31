//
//  BLEProfileItem.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/31.
//

import Foundation

struct BLEProfileItem: Identifiable {
    var id: String { deviceID }
    var deviceID: String
    var txRate: [Double]
    var txRssi: [Int]
    var rxRate: [Double]
    var rxRssi: [Int]
    var antenna: [String] //horizental vertical
    var distance: [Double]
    var timestamp: [Date]
    var test_group: [String?]
}
