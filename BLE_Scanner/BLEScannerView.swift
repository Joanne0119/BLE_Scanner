//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//

import SwiftUI
import CoreBluetooth

struct BLEScannerView: View {
    @StateObject private var scanner = CBLEScanner()

        var body: some View {
            VStack(spacing: 20) {
                Text("掃描端").font(.largeTitle).bold()
                
                Button("開始掃描") {
                    scanner.startScanning()
                }
                .buttonStyle(.borderedProminent)

                List(scanner.allPackets.values.sorted(by: { $0.deviceName < $1.deviceName })) { packet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name：\(packet.deviceName)")
                        Text("RSSI：\(packet.rssi)")
                        Text("Data：\(packet.rawData)")
                    }
                    .padding(6)
                    .background(packet.isMatched ? Color.green.opacity(0.3) : Color.clear)
                    .foregroundColor(packet.isMatched ? .green : .primary)
                    .cornerRadius(8)
                }
            }
            .padding()
        }
}
#Preview {
    BLEScannerView()
}
