//
//  BLEScannerDetailView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/27.
//  最後更新 2025/07/08

import SwiftUI
import Foundation

struct BLEScannerDetailView: View {
    @ObservedObject var packetStore: SavedPacketsStore
    @ObservedObject var scanner: CBLEScanner
    let deviceID: String
    @Environment(\.dismiss) var dismiss
//    @StateObject private var compassManager = CompassManager()
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
                        
                        SignalStrengthView(rssi: packet.rssi, hasLostSignal: packet.hasLostSignal)
                                                
                        let rssi =
                            if (currentPacket?.hasLostSignal ?? packet.hasLostSignal) { "Lost" }
                            else if (currentPacket?.rssi ?? packet.rssi != 127) { "\(currentPacket?.rssi ?? packet.rssi) dBm" }
                            else { "Error" }
                        
                        Text("\(rssi)")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.trailing, 10)
                    }
                }
                
                // 右側指南針按鈕
                ToolbarItem(placement: .navigationBarTrailing) {
                    
//                    HStack {
//                        Text("\(direction(from: compassManager.heading))")
//                            .font(.system(size: 12, weight: .medium))
//                            .foregroundColor(.white)
//                        
//                        Image(systemName: "location.north.circle")
//                            .resizable()
//                            .frame(width: 20, height: 20)
//                            .rotationEffect(Angle(degrees: -compassManager.heading))
//                            .animation(.easeInOut, value: compassManager.heading)
//                            .foregroundColor(.white)
//                    }
                    
                    HStack {
                        Button("", systemImage: "trash") {
                            packetStore.delete(packet)
                        }
                        .tint(.white)
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
    
//    private func direction(from heading: Double) -> String {
//        switch heading {
//        case 0..<22.5, 337.5..<360: return "北"
//        case 22.5..<67.5: return "東北"
//        case 67.5..<112.5: return "東"
//        case 112.5..<157.5: return "東南"
//        case 157.5..<202.5: return "南"
//        case 202.5..<247.5: return "西南"
//        case 247.5..<292.5: return "西"
//        case 292.5..<337.5: return "西北"
//        default: return "未知"
//        }
//    }
}
