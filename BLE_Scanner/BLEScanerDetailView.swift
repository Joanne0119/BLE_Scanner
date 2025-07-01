//
//  BLEScannerDetailView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/27.
//  最後更新 2025/07/01

import SwiftUI
import Foundation

enum DeviceSuggestion {
    case perfect
    case move(direction: String, distance: Int)
    case weak

    // 根據次數來初始化
    init(count: Int) {
        if count >= 100 {
            self = .perfect
        // 這是您可以根據真實函式調整的條件
        } else if count > 80 {
            self = .move(direction: "向東", distance: 1)
        } else if count > 50 {
            self = .move(direction: "向北", distance: 5)
        } else {
            self = .weak
        }
    }

    // 顯示的訊息
    var message: String {
        switch self {
        case .perfect:
            return "完美 !"
        case .move(let direction, let distance):
            return "\(direction)移動\(distance)公尺"
        case .weak:
            return "訊號微弱"
        }
    }

    // 對應的顏色
    var color: Color {
        switch self {
        case .perfect:
            return Color.green
        case .move:
            return Color.orange
        case .weak:
            return Color.red
        }
    }
}

struct BLEScannerDetailView: View {
    let packet: BLEPacket
    @Environment(\.dismiss) var dismiss
    @StateObject private var compassManager = CompassManager()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 20) {
                if let parsedData = packet.parsedData {
                    // --- 即時狀態面板 ---
                    CurrentStatusView(parsedData: parsedData)
                    
                    // --- 裝置狀態卡片 ---
                    DeviceStatusCardsView(devices: parsedData.devices)
                } else {
                    Text("沒有可解析的數據")
                        .foregroundColor(.gray)
                        .font(.body)
                        .padding(.top, 50)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // 左側返回按鈕
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
            
            // 中間的自定義標題
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Text(packet.deviceID)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 3)
                    
                    SignalStrengthView(rssi: packet.rssi)
                    
                    Text("\(packet.rssi) dBm")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.trailing, 10)
                }
            }
            
            // 右側指南針按鈕
            ToolbarItem(placement: .navigationBarTrailing) {
                
                HStack {
                    Text("\(direction(from: compassManager.heading))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    
                    Image(systemName: "location.north.circle")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .rotationEffect(Angle(degrees: -compassManager.heading))
                        .animation(.easeInOut, value: compassManager.heading)
                        .foregroundColor(.white)
                }
                
            }
        }
    }
    private func direction(from heading: Double) -> String {
        switch heading {
        case 0..<22.5, 337.5..<360: return "北"
        case 22.5..<67.5: return "東北"
        case 67.5..<112.5: return "東"
        case 112.5..<157.5: return "東南"
        case 157.5..<202.5: return "南"
        case 202.5..<247.5: return "西南"
        case 247.5..<292.5: return "西"
        case 292.5..<337.5: return "西北"
        default: return "未知"
        }
    }
}


// MARK: - 子視圖拆分

// 即時狀態的頂部資訊列
struct CurrentStatusView: View {
    let parsedData: ParsedBLEData

    var body: some View {
        HStack {
            Label("\(parsedData.seconds) s", systemImage: "clock")
                .font(.system(size: 20, weight: .medium))
            Spacer()
            Label("\(Int(parsedData.temperature)) °C", systemImage: "thermometer.medium")
                .font(.system(size: 20, weight: .medium))
            Spacer()
            Label("\(String(format: "%.2f", parsedData.atmosphericPressure)) hPa", systemImage: "gauge.medium")
                .font(.system(size: 20, weight: .medium))
        }
        .font(.headline)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// 裝置狀態卡片列表
struct DeviceStatusCardsView: View {
    let devices: [DeviceInfo]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(devices, id: \.deviceId) { device in
                let suggestion = DeviceSuggestion(count: Int(device.count))
                
                HStack {
                    Text(device.deviceId)
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                    
                    Spacer()
                    
                    Text(suggestion.message)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 25)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(suggestion.color)
                .cornerRadius(15)
            }
        }
    }
}
