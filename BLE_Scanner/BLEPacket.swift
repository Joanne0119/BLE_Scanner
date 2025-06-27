//
//  BLEPacket.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/06/27
//
import Foundation

struct BLEPacket: Identifiable, Codable, Equatable {
    var id: String { identifier }
    var deviceID: String
    var identifier: String
    var deviceName: String
    var rssi: Int
    var rawData: String
    var mask: String
    var data: String
    var isMatched: Bool
    var timestamp: Date
    var parsedData: ParsedBLEData?
}
