//
//  BLEScannerRowView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/27.
//  最後更新 2025/07/08
//

import SwiftUI

struct BLEPacketRowView: View {
    let packet: BLEPacket
    
    let scanner: CBLEScanner
    let packetStore: SavedPacketsStore
    let onSelect: (String) -> Void
    
    private var signalColor: Color {
        if packet.hasLostSignal {
            return .gray
        }
        if packet.rssi > -70 {
            return .green
        } else if packet.rssi > -90 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        // button 作為 Row 的一部分
        Button(action: {
            // 當按鈕被點擊時，呼叫傳入的 onSelect 閉包，並把 deviceID 傳出去
            onSelect(packet.deviceID)
        }) {
            HStack(spacing: 16) {
                // 左側的圓圈 ID
                Text(packet.deviceID)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(signalColor)) // signalColor 在這裡可以被正確找到

                Spacer()
                
                // 中間的訊號圖示
                SignalStrengthView(rssi: packet.rssi, hasLostSignal: packet.hasLostSignal)
                
                let rssi = if (packet.hasLostSignal) { "Lost" } else if (packet.rssi != 127) { "\(packet.rssi)" }else { "Error" }
                 
                // 右側的 RSSI 數值
                Text("\(rssi)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
