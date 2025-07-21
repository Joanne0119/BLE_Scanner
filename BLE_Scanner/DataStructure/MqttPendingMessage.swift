//
//  MqttPendingMessage.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/21.
//

import Foundation

struct PendingMessage: Codable {
    let topic: String
    let payload: String
    let timestamp: Date 
}
