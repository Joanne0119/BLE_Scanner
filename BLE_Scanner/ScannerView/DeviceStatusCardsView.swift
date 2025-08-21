//
//  DeviceStatusCardsView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//  最後更新 2025/07/23

import Foundation
import SwiftUI

enum DeviceSuggestion {
    case perfect
    case move(distance: Int)
    case weak

    // 根據次數來初始化
    init(rate: Double) {
        if rate >= 5 {
            self = .perfect
        // 這是您可以根據真實函式調整的條件
        } else if rate > 3 {
            self = .move(distance: 3)
        } else if rate > 1 {
            self = .move(distance: 6)
        } else {
            self = .weak
        }
    }

    // 顯示的訊息
    var message: String {
        switch self {
        case .perfect:
            return "完美 !"
        case .move(let distance):
            return "靠近\(distance)公尺"
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

// 裝置狀態卡片列表
struct DeviceStatusCardsView: View {
    let allHistoricalDevices: [DeviceInfo]
    let currentDeviceIDs: Set<String>
    
    @State private var expandedDeviceId: String? = nil

    // 將所有數據按 deviceId 分組
    private var groupedDevices: [String: [DeviceInfo]] {
        let sorted = allHistoricalDevices.sorted { $0.timestamp > $1.timestamp }
        let recentRecords = sorted.prefix(100)
        return Dictionary(grouping: recentRecords, by: { $0.deviceId })
    }

    // 取得每個裝置的最新數據（即時數據）
    private var currentDisplayDevices: [DeviceInfo] {
        return currentDeviceIDs.compactMap { deviceId in
            // 對於每個當前活躍的裝置ID，找到其最新的數據
            return groupedDevices[deviceId]?.first
        }.sorted { $0.receptionRate > $1.receptionRate }
    }
    
    private func getAverageRate(for deviceId: String) -> Double {
        // 根據 ID 取得該裝置的所有歷史數據
        guard let deviceHistory = groupedDevices[deviceId], deviceHistory.count > 1 else {
            return 0.0
        }
        
        let historicalRecords = deviceHistory.dropFirst()
        
        // 將所有 receptionRate 加總
        let totalRate = historicalRecords.reduce(0.0) { $0 + $1.receptionRate }
        
        // 計算平均值並回傳
        return totalRate / Double(historicalRecords.count)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(currentDisplayDevices) { currentDevice in
                VStack(spacing: 0) {
                    // 第一層：顯示即時數據
                    DeviceCardView(
                        device: currentDevice,
                        isHistory: false,
                        averageRate: getAverageRate(for: currentDevice.deviceId)
                    )
                        .onTapGesture {
                            withAnimation(.spring()) {
                                expandedDeviceId = (expandedDeviceId == currentDevice.deviceId) ? nil : currentDevice.deviceId
                            }
                        }
                    
                    // 展開後：顯示該裝置的所有歷史數據（除了最新的）
                    if expandedDeviceId == currentDevice.deviceId {
                        let historicalDevices = groupedDevices[currentDevice.deviceId]?.dropFirst() ?? []
                        
                        ForEach(Array(historicalDevices)) { historicalDevice in
                            DeviceCardView(device: historicalDevice, isHistory: true, averageRate: 0)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                        }
                    }
                }
            }
        }
    }
}
// 將單張卡片的 UI 拆分成獨立的 View，方便重用
struct DeviceCardView: View {
    let device: DeviceInfo
    var isHistory: Bool = false // 用來區分是否為歷史紀錄
    let averageRate: Double
    
    private let suggestion: DeviceSuggestion
    
    init(device: DeviceInfo, isHistory: Bool = false, averageRate: Double) {
        self.device = device
        self.isHistory = isHistory
        self.averageRate = averageRate
        self.suggestion = DeviceSuggestion(rate: device.receptionRate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 頂部的時間戳和標記
            HStack {
                Text("\(formatTime(device.timestamp))")
                    .font(.caption)
                    .foregroundColor(isHistory ? .white.opacity(0.8) : .white)
                
                Spacer()
                HStack {
                    if !isHistory && device.count >= 100 {
                        Text("已達標")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundColor(suggestion.color)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    if !isHistory {
                        Text("平均 \(String(format: "%.1f", averageRate)) 次/秒")
                    }
                }
            }
            
            // 中間的主要資訊
            HStack {
                Text(device.deviceId)
                    .font(isHistory ? .title : .system(size: 55, weight: .bold, design: .rounded))
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(String(format: "%.1f", device.receptionRate)) 次/秒")
                        .font(isHistory ? .body : .system(size: 36, weight: .semibold, design: .rounded))
//                    
//                    if !isHistory {
//                        Text(suggestion.message)
//                            .font(.system(size: 30, weight: .semibold, design: .rounded))
//                    }
                }
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(isHistory ? suggestion.color.opacity(0.7) : suggestion.color) // 歷史紀錄顏色稍淡
        .cornerRadius(15)
        .padding(.top, isHistory ? 2 : 0) // 歷史紀錄和主卡片間留點空隙
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
