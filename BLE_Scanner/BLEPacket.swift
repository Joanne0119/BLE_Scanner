//
//  BLEPacket.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//
import Foundation

struct BLEPacket: Identifiable {
    let id = UUID()
    let identifier: String
    let deviceName: String
    let rssi: Int
    let rawData: String
    let isMatched: Bool
}
