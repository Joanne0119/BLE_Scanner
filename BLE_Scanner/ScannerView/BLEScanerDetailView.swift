//
//  BLEScannerDetailView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/27.
//  最後更新 2025/07/02

import SwiftUI
import Foundation

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

struct BLEScannerDetailView: View {
    @ObservedObject var packetStore: SavedPacketsStore
    @ObservedObject var scanner: CBLEScanner
    let deviceID: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var compassManager = CompassManager()
    @State private var hasBeenSaved = false
    @State private var lastSavedCycle: Date?  // 記錄上次保存的時間，用於防止重複保存
    
    private var currentPacket: BLEPacket? {
        scanner.matchedPackets[deviceID]
    }
    
    private var storedPacket: BLEPacket? {
        packetStore.packets.first { $0.deviceID == deviceID }
    }
    
    private var displayPacket: BLEPacket? {
        guard var packetForDisplay = currentPacket else {
            return storedPacket
        }
        
        // 將歷史數據添加到即時數據後面
        if let historyDevices = storedPacket?.parsedData?.devices {
            let currentDevices = packetForDisplay.parsedData?.devices ?? []
            // 即時數據在前，歷史數據在後
            packetForDisplay.parsedData?.devices = currentDevices + historyDevices
        }
        
        return packetForDisplay
    }
    
    private var historicalDevices: [DeviceInfo] {
        return storedPacket?.parsedData?.devices ?? []
    }

    
    // 檢查是否需要重置狀態
    private func shouldResetState() -> Bool {
        guard let currentParsedData = currentPacket?.parsedData else { return false }
        
        // 檢查當前封包中的所有裝置計數是否都小於100
        let allDevicesBelowTarget = currentParsedData.devices.allSatisfy { $0.count < 100 }
        
        // 如果之前已經保存過，並且現在所有裝置都低於目標，則需要重置
        return hasBeenSaved && allDevicesBelowTarget
    }

    var body: some View {
        
        if let packet = displayPacket {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 20) {
                    if let parsedData = packet.parsedData {
                        // --- 即時狀態面板 ---
                        CurrentStatusView(parsedData: parsedData)
                        
                        // --- 裝置狀態卡片 ---
                        DeviceStatusCardsView(
                            // 包含所有歷史的 devices 陣列
                            allHistoricalDevices: parsedData.devices,
                            // 即時封包中提取當前的裝置ID集合並傳遞
                            currentDeviceIDs: Set((currentPacket?.parsedData?.devices ?? []).map { $0.deviceId })
                        )
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
                        
                        SignalStrengthView(rssi: currentPacket?.rssi ?? packet.rssi)
                                                
                        
                        Text("\(currentPacket?.rssi ?? packet.rssi) dBm")
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
            .onChange(of: currentPacket) { newPacket in
                print("onChange 觸發")
                
                // 首先檢查是否需要重置狀態
                if shouldResetState() {
                    print("--- 檢測到重置條件，重置狀態 ---")
                    hasBeenSaved = false
                    lastSavedCycle = nil
                    print("hasBeenSaved 已重置為 false")
                    return
                }
                
                // 檢查是否需要保存
                guard let packetToSave = newPacket,
                      packetToSave.parsedData?.hasReachedTarget == true,
                      !hasBeenSaved
                else {
                    print("不符合保存條件:")
                    print("- hasReachedTarget: \(newPacket?.parsedData?.hasReachedTarget ?? false)")
                    print("- hasBeenSaved: \(hasBeenSaved)")
                    return
                }
                
                // 防止在短時間內重複保存同一個週期的數據
                let currentTime = Date()
                if let lastSaved = lastSavedCycle,
                   currentTime.timeIntervalSince(lastSaved) < 5.0 {
                    print("距離上次保存時間過短，跳過保存")
                    return
                }
                
                print("--- 自動儲存觸發！Device ID: \(packetToSave.deviceID) ---")
                packetStore.updateOrAppendDeviceHistory(for: packetToSave)
                
                // 設定保存狀態和時間
                hasBeenSaved = true
                lastSavedCycle = currentTime
                
                print("已儲存並設置 hasBeenSaved = true")
                
                // 輸出當前達標的裝置信息
                if let devices = packetToSave.parsedData?.devices {
                    let reachedTargetDevices = devices.filter { $0.count >= 100 }
                    print("達標裝置數量: \(reachedTargetDevices.count)")
                    for device in reachedTargetDevices {
                        print("- 裝置 \(device.deviceId): \(device.count) 次")
                    }
                }
            }
        }
        else {
            Text("裝置資料不存在或已過期")
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                    }
                    .tint(.blue)
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
    let allHistoricalDevices: [DeviceInfo]
    let currentDeviceIDs: Set<String>
    
    @State private var expandedDeviceId: String? = nil

    // 將所有數據按 deviceId 分組
    private var groupedDevices: [String: [DeviceInfo]] {
        let sorted = allHistoricalDevices.sorted { $0.timestamp > $1.timestamp }
        return Dictionary(grouping: sorted, by: { $0.deviceId })
    }

    // 取得每個裝置的最新數據（即時數據）
    private var currentDisplayDevices: [DeviceInfo] {
        return currentDeviceIDs.compactMap { deviceId in
            // 對於每個當前活躍的裝置ID，找到其最新的數據
            return groupedDevices[deviceId]?.first
        }.sorted { $0.receptionRate > $1.receptionRate }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(currentDisplayDevices) { currentDevice in
                VStack(spacing: 0) {
                    // 第一層：顯示即時數據
                    DeviceCardView(device: currentDevice)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                expandedDeviceId = (expandedDeviceId == currentDevice.deviceId) ? nil : currentDevice.deviceId
                            }
                        }
                    
                    // 展開後：顯示該裝置的所有歷史數據（除了最新的）
                    if expandedDeviceId == currentDevice.deviceId {
                        let historicalDevices = groupedDevices[currentDevice.deviceId]?.dropFirst() ?? []
                        
                        ForEach(Array(historicalDevices)) { historicalDevice in
                            DeviceCardView(device: historicalDevice, isHistory: true)
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
    
    private let suggestion: DeviceSuggestion
    
    init(device: DeviceInfo, isHistory: Bool = false) {
        self.device = device
        self.isHistory = isHistory
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
            }
            
            // 中間的主要資訊
            HStack {
                Text(device.deviceId)
                    .font(isHistory ? .title : .system(size: 50, weight: .bold, design: .rounded))
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(String(format: "%.1f", device.receptionRate)) 次/秒")
                        .font(isHistory ? .body : .system(size: 25, weight: .semibold, design: .rounded))
                    
                    if !isHistory {
                        Text(suggestion.message)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                    }
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
