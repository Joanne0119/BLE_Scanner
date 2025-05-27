//
//  StorageManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//
import Foundation
import SwiftUI

struct StorageManager {
    static let storageKey = "savedPackets"

    static func save(packets: [BLEPacket]) {
        if let encoded = try? JSONEncoder().encode(packets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            NotificationCenter.default.post(name: .packetsUpdated, object: nil)
        }
    }
    
    static func append(packets newPackets: [BLEPacket]) {
        var current = load()
        current.append(contentsOf: newPackets)
        save(packets: current)
    }

    static func load() -> [BLEPacket] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BLEPacket].self, from: data) else {
            return []
        }
        return decoded
    }
}

// SavedPacketsStore
class SavedPacketsStore: ObservableObject {
    @Published var packets: [BLEPacket] = []

    init() {
        packets = StorageManager.load()
    }

    func append(_ newPackets: [BLEPacket]) {
        packets.append(contentsOf: newPackets)
        StorageManager.save(packets: packets)
    }

    func reload() {
        packets = StorageManager.load()
    }
    
    func delete(_ packet: BLEPacket) {
        if let index = packets.firstIndex(where: { $0.id == packet.id }) {
            packets.remove(at: index)
            StorageManager.save(packets: packets)
        }
    }

    func clear() {
        packets = []
        StorageManager.save(packets: [])
    }
}

