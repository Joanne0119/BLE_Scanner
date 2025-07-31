//
//  BLEScannerDetailView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/27.
//  最後更新 2025/07/31

import SwiftUI
import Foundation

struct BLEScannerDetailView: View {
    @ObservedObject var packetStore: SavedPacketsStore
    @ObservedObject var scanner: CBLEScanner
    let deviceID: String
    @Environment(\.dismiss) var dismiss
    @State private var showSheet = false;
    
    @State private var hasBeenSaved = false
    @State private var lastSavedCycle: Date?
    @State private var selectedTestGroupID: String?
    
    let mockItem = BLEProfileItem(
        deviceID: "04",
        txRate: [5.2, 4.8, 3.2, 5.0, 4.5, 2.9],
        txRssi: [-65, -72, -81, -68, -75, -83],
        rxRate: [5.0, 4.6, 3.0, 4.9, 4.4, 2.8],
        rxRssi: [-68, -75, -84, -70, -77, -85],
        antenna: ["vertical", "horizental", "vertical", "horizental", "vertical", "horizental"],
        distance: [5, 5, 10, 10, 15, 15],
        timestamp: [Date(), Date(), Date(), Date(), Date(), Date()],
        test_group: [nil, nil,nil,nil,nil,nil]
    )
    
    private var currentPacket: BLEPacket? {
        scanner.matchedPackets[deviceID]
    }
    
    // 獲取該 deviceID 下的所有測試組（包含即時測試組）
    private var testGroups: [String] {
        var groups = Set<String>()
        
        // 從儲存的封包中獲取歷史測試組
        let storedGroups = packetStore.packets
            .filter { $0.deviceID == deviceID }
            .compactMap { $0.testGroupID }
        groups.formUnion(storedGroups)
        
        // 從即時封包中獲取當前測試組
        if let currentTestGroupID = currentPacket?.testGroupID {
            groups.insert(currentTestGroupID)
        }
        
        return Array(groups).sorted { group1, group2 in
            // 按時間排序，最新的在前
            return group1 > group2
        }
    }
    
    // 獲取當前即時測試組ID
    private var currentTestGroupID: String? {
        return currentPacket?.testGroupID
    }
    
    // 獲取指定測試組的封包
    private func getPacket(for testGroupID: String) -> BLEPacket? {
        return packetStore.packets.first {
            $0.deviceID == deviceID && $0.testGroupID == testGroupID
        }
    }
    
    // 獲取當前顯示的封包（合併歷史數據）
    private func getDisplayPacket(for testGroupID: String) -> BLEPacket? {
        // 如果選中的是當前即時測試組，優先使用即時數據
        if let currentTestGroupID = currentTestGroupID,
           testGroupID == currentTestGroupID,
           let current = currentPacket {
            
            // 檢查是否有對應的歷史數據需要合併
            if let basePacket = getPacket(for: testGroupID) {
                // 將歷史數據添加到即時數據後面
                if let historyDevices = basePacket.parsedData?.devices {
                    let currentDevices = current.parsedData?.devices ?? []
                    var mergedCurrent = current
                    mergedCurrent.parsedData?.devices = currentDevices + historyDevices
                    return mergedCurrent
                }
            }
            
            // 如果沒有歷史數據，直接返回即時數據
            return current
        }
        
        // 否則返回儲存的歷史數據
        return getPacket(for: testGroupID)
    }
    
    // 檢查是否需要重置狀態
    private func shouldResetState() -> Bool {
        guard let currentParsedData = currentPacket?.parsedData else { return false }
        let allDevicesBelowTarget = currentParsedData.devices.allSatisfy { $0.count < 100 }
        return hasBeenSaved && allDevicesBelowTarget
    }

    var body: some View {
        // 外層縱向 ScrollView
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 20) {
                
                // === 即時狀態面板 ===
                if let currentParsedData = currentPacket?.parsedData {
                    CurrentStatusView(parsedData: currentParsedData)
                }
                
                // === 測試組選擇器（內層橫向 ScrollView）===
                TestGroupSelectorView(
                    testGroups: testGroups,
                    selectedTestGroupID: $selectedTestGroupID,
                    currentTestGroupID: currentTestGroupID
                )
                
                // === 選中測試組的詳細數據 ===
                if let selectedGroupID = selectedTestGroupID ?? testGroups.first,
                   let displayPacket = getDisplayPacket(for: selectedGroupID) {
                    
                    TestGroupDetailView(
                        packet: displayPacket,
                        testGroupID: selectedGroupID,
                        currentDeviceIDs: Set((currentPacket?.parsedData?.devices ?? []).map { $0.deviceId }),
                        isCurrentGroup: selectedGroupID == currentTestGroupID,  // 標示是否為當前測試組
                        onClearHistory: {
                            packetStore.deleteByTestGroupID(selectedGroupID)
                            selectedTestGroupID = currentTestGroupID ?? testGroups.first
//                            if getPacket(for: selectedGroupID) != nil {
//                                packetStore.clearDeviceHistoryByTestGroup(testGroupID: selectedGroupID)
//                            }
                        }
                    )
                } else {
                    Text("沒有資料")
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
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
            
            // 中間標題
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Text(deviceID)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 3)
                    
                    if let current = currentPacket {
                        SignalStrengthView(rssi: current.rssi, hasLostSignal: current.hasLostSignal)
                        
                        let rssi = current.hasLostSignal ? "Lost" :
                                  (current.rssi != 127 ? "\(current.rssi) dBm" : "Error")
                        
                        Text(rssi)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.trailing, 10)
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showSheet.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: currentPacket) { newPacket in
            handlePacketChange(newPacket)
        }
        .onChange(of: currentTestGroupID) { newTestGroupID in
            // 當即時測試組改變時，自動切換到新的測試組
            if let newGroupID = newTestGroupID,
               selectedTestGroupID != newGroupID {
                print("檢測到新的測試組: \(newGroupID)，自動切換顯示")
                selectedTestGroupID = newGroupID
            }
        }
        .onAppear {
            if selectedTestGroupID == nil {
                selectedTestGroupID = currentTestGroupID ?? testGroups.first
            }
        }
        .sheet(isPresented: $showSheet) {
            SheetView(item: mockItem)
                .padding()
        }
    }
    
    private func handlePacketChange(_ newPacket: BLEPacket?) {
        print("onChange 觸發")
        
        if shouldResetState() {
            print("--- 檢測到重置條件，重置狀態 ---")
            hasBeenSaved = false
            lastSavedCycle = nil
            return
        }
        
        guard let packetToSave = newPacket,
              packetToSave.parsedData?.hasReachedTarget == true,
              !hasBeenSaved,
              let testGroupID = packetToSave.testGroupID else {
            return
        }
        
        let currentTime = Date()
        if let lastSaved = lastSavedCycle,
           currentTime.timeIntervalSince(lastSaved) < 5.0 {
            return
        }
        
        print("--- 自動儲存觸發！Device ID: \(packetToSave.deviceID), TestGroup: \(testGroupID) ---")
        
        packetStore.updateOrAppendByTestGroupID(for: packetToSave)
        
        selectedTestGroupID = testGroupID
        
        hasBeenSaved = true
        lastSavedCycle = currentTime
    }
}

// === Sheet View ===
struct SheetView: View {
    let item: BLEProfileItem
    
    var body: some View {
        let newDistances = item.distance.removingDuplicates()
        
        VStack {
        
            Text(item.id)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(Circle().fill(.gray))
        
            HStack {
                Text(" ")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("天線方向")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(newDistances, id: \.self) { dis in
                    Text("\(String(format: "%.1f",dis)) m")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.white)
                        .overlay(
                            Rectangle().stroke(Color.gray, lineWidth: 1)
                        )
                }
                
            }
            HStack {
                Text("Tx (次/秒)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("垂直")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.txRate.enumerated()), id: \.offset) { index, tx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "vertical") {
                            Text("\(String(format: "%.1f",tx))")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Tx (dBm)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("垂直")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.txRssi.enumerated()), id: \.offset) { index, tx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "vertical") {
                            Text("\(tx)")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Tx (次/秒)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("水平")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.txRate.enumerated()), id: \.offset) { index, tx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "horizental") {
                            Text("\(String(format: "%.1f",tx))")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Tx (dBm)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("水平")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.txRssi.enumerated()), id: \.offset) { index, tx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "horizental") {
                            Text("\(tx)")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Rx (次/秒)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("垂直")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.rxRate.enumerated()), id: \.offset) { index, rx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "vertical") {
                            Text("\(String(format: "%.1f",rx))")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Rx (dBm)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("垂直")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.rxRssi.enumerated()), id: \.offset) { index, rx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "vertical") {
                            Text("\(rx)")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Rx (次/秒)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("水平")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.rxRate.enumerated()), id: \.offset) { index, rx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "horizental") {
                            Text("\(String(format: "%.1f",rx))")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            HStack {
                Text("Rx (dBm)")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                Text("水平")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white)
                    .overlay(
                        Rectangle().stroke(Color.gray, lineWidth: 1)
                    )
                ForEach(Array(item.rxRssi.enumerated()), id: \.offset) { index, rx in
                    ForEach(newDistances, id: \.self){ dis in
                        if(item.distance[index] == dis && item.antenna[index] == "horizental") {
                            Text("\(rx)")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color.white)
                                .overlay(
                                    Rectangle().stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            
        }
    }
}

// === Test Group Selector Group ===
struct TestGroupSelectorView: View {
    let testGroups: [String]
    @Binding var selectedTestGroupID: String?
    let currentTestGroupID: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    
                    ForEach(testGroups, id: \.self) { groupID in
                        TestGroupTagView(
                            testGroupID: groupID,
                            isSelected: selectedTestGroupID == groupID,
                            isCurrent: groupID == currentTestGroupID,
                            onTap: {
                                selectedTestGroupID = groupID
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// === Test Group Label ===
struct TestGroupTagView: View {
    let testGroupID: String
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    
    private var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        
        if let date = formatter.date(from: testGroupID) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM/dd HH:mm"
            return displayFormatter.string(from: date)
        }
        
        return testGroupID
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 18, weight: .medium))
                    
                    
                    if isCurrent {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isCurrent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isCurrent ? Color.green.opacity(0.2) :  // 當前測試組用綠色
                        isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
                    )
            )
            .foregroundColor(
                isCurrent ? .green :
                isSelected ? .blue : .primary
            )
        }
    }
}

// === Test Group Info ===
struct TestGroupDetailView: View {
    let packet: BLEPacket
    let testGroupID: String
    let currentDeviceIDs: Set<String>
    let isCurrentGroup: Bool
    let onClearHistory: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(testGroupID)")
                            .font(.headline)
                        
                        
                        if isCurrentGroup {
                            Text("LIVE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    Text("更新時間: \(packet.timestamp, formatter: timeFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onClearHistory) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            if let parsedData = packet.parsedData {
                DeviceStatusCardsView(
                    allHistoricalDevices: parsedData.devices,
                    currentDeviceIDs: currentDeviceIDs
                )
            }
        }
        .padding()
        .background(
            (isCurrentGroup ? Color.green.opacity(0.05) : Color.gray.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
