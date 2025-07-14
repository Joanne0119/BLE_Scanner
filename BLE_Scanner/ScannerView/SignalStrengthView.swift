//
//  SignalStrengthView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//  最後更新 2025/07/14

import SwiftUI

struct SignalStrengthView: View {
    let rssi: Int
    var hasLostSignal: Bool = false
    
    // 根據 RSSI 值決定顏色
    private var signalColor: Color {
        if hasLostSignal {
            return .gray
        }
        if rssi == 127 {
            return .red
        } else if rssi > -70 {
            return .green
        } else if rssi > -90 {
            return .orange
        } else {
            return .red
        }
    }
    
    // 根據 RSSI 值決定要顯示幾格訊號
    private var numberOfBars: Int {
        if (rssi == 127 || hasLostSignal) {
            return 0
        }
        else if rssi > -65 {
            return 4
        } else if rssi > -80 {
            return 3
        } else if rssi > -95 {
            return 2
        } else {
            return 1
        }
    }
    
    // 定義四個長方形的高度
    private let barHeights: [CGFloat] = [12, 18, 24, 30]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<barHeights.count, id: \.self) { index in
                Rectangle()
                    // 如果這個長方形的 index 小於要顯示的格數，就用實色，否則用透明色
                    .fill(index < numberOfBars ? signalColor : signalColor.opacity(0.3))
                    .frame(width: 6, height: barHeights[index])
            }
        }
        .cornerRadius(3)
    }
}
