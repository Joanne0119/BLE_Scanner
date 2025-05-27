//
//  BLEPacket.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/05/23
//
import Foundation

struct BLEPacket: Identifiable {
    let id = UUID()
    let deviceID: String
    let identifier: String
    let deviceName: String
    let rssi: Int
    let rawData: String
    let mask: String
    let data: String
    let isMatched: Bool
}
