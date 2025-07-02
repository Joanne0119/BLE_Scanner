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
    
    private var currentPacket: BLEPacket? {
        scanner.matchedPackets[deviceID]
    }
    
    private var storedPacket: BLEPacket? {
        packetStore.packets.first { $0.deviceID == deviceID }
    }
    
    private var displayPacket: BLEPacket? {
        //  必須要有即時封包，否則 UI 無法即時更新
        guard var packetForDisplay = currentPacket else {
            // 如果沒有即時資料 (例如剛停止掃描)，則顯示儲存的資料作為備用
            return storedPacket
        }

        //  檢查是否有歷史紀錄
        if let historyDevices = storedPacket?.parsedData?.devices {
            //    將完整的歷史紀錄注入到我們用於顯示的封包中
            //    如果 packetForDisplay.parsedData 是 nil，這行不會做事，是安全的
            packetForDisplay.parsedData?.devices = historyDevices
        }
        
        //  回傳這個混合了「即時頂層數據」和「完整歷史列表」的完美封包
        return packetForDisplay
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
                print("onChang")
                guard let packetToSave = newPacket,
                      packetToSave.parsedData?.hasReachedTarget == true,
                      !hasBeenSaved
                else {
                    print(newPacket?.parsedData?.hasReachedTarget ?? false)
                    return
                }
                
                print("--- 自動儲存觸發！Device ID: \(packetToSave.deviceID) ---")
                packetStore.updateOrAppendDeviceHistory(for: packetToSave)
                
                hasBeenSavedTimer()
                
                
            }
            .onDisappear(){
                hasBeenSaved = false
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
    private func hasBeenSavedTimer() {
        hasBeenSaved = true
        print("--- 儲存功能已鎖定，10秒後解鎖 ---")

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            //10 秒後，執行這段程式碼，解除鎖定
            self.hasBeenSaved = false
            print("--- [偵錯] 儲存功能已解鎖 ---")
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
    
    // 【新增】用來追蹤哪個裝置的歷史紀錄被展開了
    @State private var expandedDeviceId: String? = nil

    // 【新增】將傳入的 devices 陣列按 deviceId 分組，並按時間戳排序
    private var groupedDevices: [String: [DeviceInfo]] {
        let sorted = allHistoricalDevices.sorted { $0.timestamp > $1.timestamp }
        let result = Dictionary(grouping: sorted, by: { $0.deviceId })
        
        return result
    }

    // 取得每個分組中最新的一筆紀錄，並按時間戳排序
    private var uniqueLatestDevices: [DeviceInfo] {
        groupedDevices
            .compactMap { $0.value.first } // 先取得所有歷史裝置的最新一筆
            .filter { currentDeviceIDs.contains($0.deviceId) } // 只保留那些ID存在於「當前掃描」中的裝置
            .sorted { $0.timestamp > $1.timestamp } // 最後對結果進行排序
    }
    
    var body: some View {
        // 判斷總紀錄是否大於5筆，來決定是否啟用折疊功能
        
        if allHistoricalDevices.count > 5 {
            // --- 折疊模式 ---
            VStack(spacing: 6) {
                ForEach(uniqueLatestDevices) { latestDevice in
                    VStack(spacing: 0) {
                        // 顯示最新一筆紀錄的卡片
                        DeviceCardView(device: latestDevice)
                            .onTapGesture {
                                // 點擊時切換展開狀態
                                print("--- 卡片被點擊 ---")
                                print("點擊的 Device ID: \(latestDevice.deviceId)")
                                print("點擊前的 expandedDeviceId: \(String(describing: expandedDeviceId))")
                               
                                withAnimation(.spring()) {
                                    if expandedDeviceId == latestDevice.deviceId {
                                        expandedDeviceId = nil // 如果已經展開，則收合
                                    } else {
                                        expandedDeviceId = latestDevice.deviceId // 否則展開
                                    }
                                }
                                print("點擊後的 expandedDeviceId: \(String(describing: expandedDeviceId))")
                                print("--------------------------")
                            }
                        
                        // 如果當前裝置被設定為展開，則顯示其歷史紀錄
                        if expandedDeviceId == latestDevice.deviceId {
                            let _ = print("--- 展開歷史紀錄 ---")
                            let _ = print("要展開的 Device ID: \(latestDevice.deviceId)")
                            // 取得除了最新一筆以外的所有歷史紀錄
                            let historicalDevices = groupedDevices[latestDevice.deviceId]?.dropFirst() ?? []
                            
                            let _ = print("找到的歷史紀錄筆數: \(historicalDevices.count)")
                            let _ = print("--------------------------")
                            
                            ForEach(Array(historicalDevices)) { historicalDevice in
                                DeviceCardView(device: historicalDevice, isHistory: true)
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity.combined(with: .move(edge: .bottom))))
                            }
                        }
                    }
                }
            }
        } else {
            // --- 全部顯示模式 ---
            VStack(spacing: 6) {
                ForEach(allHistoricalDevices) { device in
                    DeviceCardView(device: device)
                }
            }
        }
    }
}

// 【新增】將單張卡片的 UI 拆分成獨立的 View，方便重用
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
