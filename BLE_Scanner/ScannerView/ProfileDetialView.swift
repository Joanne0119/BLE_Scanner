//
//  ProfileDetailView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/8/8.
//

import SwiftUI

enum ExecutionState {
    case idle
    case running(startTime: Date, captures: [(tx: Int, rx: Int8)])
    case completed(avgTx: Double, avgRx: Double)
}
extension ExecutionState: Equatable {
    static func == (lhs: ExecutionState, rhs: ExecutionState) -> Bool {
        switch (lhs, rhs) {
        
        case (.idle, .idle):
            return true
            
        case let (.completed(lhsAvgTx, lhsAvgRx), .completed(rhsAvgTx, rhsAvgRx)):
            return lhsAvgTx == rhsAvgTx && lhsAvgRx == rhsAvgRx
            
        case let (.running(lhsStartTime, lhsCaptures), .running(rhsStartTime, rhsCaptures)):

            return lhsStartTime == rhsStartTime &&
                   lhsCaptures.elementsEqual(rhsCaptures) { $0.tx == $1.tx && $0.rx == $1.rx }
        default:
            return false
        }
    }
}


struct ProfileDetailView: View {
    @ObservedObject var scanner: CBLEScanner
    let deviceID: String
    
    // 從外部傳入 SavedPacketsStore，它是資料的真實來源
    @EnvironmentObject var savedPacketsStore: SavedPacketsStore
    
    @Environment(\.dismiss) var dismiss
    
    @State private var showDeleteConfirmAlert = false
    
    private var currentPacket: BLEPacket? {
        scanner.matchedPackets[deviceID]
    }

    private var displayPackets: Binding<[BLEPacket]> {
        Binding(
            get: {
                let testID = currentPacket?.testGroupID ?? ""
                return savedPacketsStore.packets.filter { $0.testGroupID == testID }
            },
            set: { newPackets in
                
                let testID = currentPacket?.testGroupID ?? ""
                savedPacketsStore.packets.removeAll { $0.testGroupID == testID }
                savedPacketsStore.packets.append(contentsOf: newPackets)
            }
        )
    }
    
    @State private var showEditSheet = false
    @State private var editingPacketID: String?

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    HStack {
                        Text(currentPacket?.testGroupID ?? "LOADING...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // ForEach 現在會正確顯示篩選後的封包
                    ForEach(displayPackets) { $packet in
                        ProfileCardView(
                            scanner: scanner,
                            deviceID: deviceID,
                            packet: $packet,
                            onEdit: { packetID in
                                self.editingPacketID = packetID
                                self.showEditSheet = true
                            }
                        )
                    }
                }
                .padding(.vertical)
            }
        }
        .onAppear(perform: setupInitialPackets)
        .onReceive(scanner.profileResultPublisher) { result in
            // 當收到廣播結果時，直接呼叫儲存函式
            self.saveResult(
                for: result.packetID,
                avgTx: result.avgTx,
                avgRx: result.avgRx,
                capturedTxs: result.capturedTxs,
                capturedRxs: result.capturedRxs
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            createToolbar()
        }
        .sheet(isPresented: $showEditSheet) {
            if let editingID = editingPacketID,
               let index = savedPacketsStore.packets.firstIndex(where: { $0.id == editingID }) {
                ProfileEditSheet(packet: $savedPacketsStore.packets[index])
            }
        }
        .alert("確認刪除", isPresented: $showDeleteConfirmAlert) {
            Button("取消", role: .cancel) { }
            Button("確定刪除", role: .destructive) {
                savedPacketsStore.deleteAllProfileData(for: deviceID)
                dismiss()
            }
        } message: {
            Text("確定要刪除節點 \(deviceID) 的所有 Profile 測試資料嗎？此操作無法復原")
        }
    }
    
    private func setupInitialPackets() {
        guard let testID = currentPacket?.testGroupID else {
            print("無法獲取 Test Group ID，無法創建初始封包。")
            return
        }

        let existingPackets = savedPacketsStore.packets.filter { $0.testGroupID == testID }
        if !existingPackets.isEmpty {
            print("testID \(testID) 的封包已存在，無需創建。")
            return
        }
        
        print("為 testID \(testID) 首次創建初始測試封包...")

        // 定義您想要的預設測試組合
        let defaultTestMethods = [
            "5m_Vertical", "5m_Horizontal",
            "10m_Vertical", "10m_Horizontal",
            "15m_Vertical", "15m_Horizontal"
        ]
        
        var newPackets: [BLEPacket] = []
        
        for method in defaultTestMethods {
            let newPacket = BLEPacket(
                deviceID: self.deviceID,
                identifier: UUID().uuidString, // 給每個卡片一個唯一的 ID
                deviceName: currentPacket?.deviceName ?? "N/A",
                rssi: 0,
                rawData: "",
                mask: "",
                data: "",
                isMatched: true,
                timestamp: Date(),
                parsedData: nil,
                profileData: ProfileData(phone_rssi: 0, testMethod: method, avgTx: nil, avgRx: nil),
                hasLostSignal: false,
                testGroupID: testID,
                receptionCount: 0
            )
            newPackets.append(newPacket)
        }
        
        // 將新創建的封包加入到 store 中
        savedPacketsStore.packets.append(contentsOf: newPackets)
         savedPacketsStore.save()
    }
    
    private func saveResult(
        for packetID: String,
        avgTx: Double,
        avgRx: Double,
        capturedTxs: [Int],
        capturedRxs: [Int8]
    ) {
        savedPacketsStore.saveAndPublishProfileResult(
            for: packetID,
            avgTx: avgTx,
            avgRx: avgRx,
            capturedTxs: capturedTxs,
            capturedRxs: capturedRxs
        )
        
        print("儲存與發布指令已觸發 (Packet ID: \(packetID))")
    }


    @ToolbarContentBuilder
    private func createToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                Text(deviceID)
                    .font(.system(size: 31, weight: .bold))
                
                if let packet = currentPacket {
                    // This is a placeholder for your SignalStrengthView
                     SignalStrengthView(rssi: packet.rssi, hasLostSignal: packet.hasLostSignal)
                    
                    let rssiText = packet.hasLostSignal ? "Lost" : "\(packet.rssi) dBm"
                    Text(rssiText)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(role: .destructive) {
                showDeleteConfirmAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Profile Edit Sheet View

struct ProfileEditSheet: View {
    @Binding var packet: BLEPacket
    @Environment(\.dismiss) var dismiss

    @State private var selectedDistance: String
    @State private var selectedDirection: String
    
    let distances = ["5m", "10m", "15m"]
    let directions = ["Vertical", "Horizontal"]

    init(packet: Binding<BLEPacket>) {
        self._packet = packet
        
        let components = packet.wrappedValue.profileData?.testMethod.components(separatedBy: "_") ?? ["5m", "Vertical"]
        self._selectedDistance = State(initialValue: components.first ?? "5m")
        self._selectedDirection = State(initialValue: components.last ?? "Vertical")
    }
    var body: some View {
        VStack(spacing: 30) {
            Text("設定測試參數")
                .font(.largeTitle.bold())

            // Distance Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("距離")
                    .font(.title2.bold())
                HStack(spacing: 15) {
                    ForEach(distances, id: \.self) { dist in
                        Button(action: { selectedDistance = dist }) {
                            Text(dist)
                                .font(.title3.weight(.medium))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedDistance == dist ? Color.gray.opacity(0.8) : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }

            // Antenna Direction Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("天線方向")
                    .font(.title2.bold())
                HStack(spacing: 15) {
                    ForEach(directions, id: \.self) { dir in
                        Button(action: { selectedDirection = dir }) {
                            Text(dir)
                                .font(.title3.weight(.medium))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedDirection == dir ? Color.gray.opacity(0.8) : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }

            Spacer()

            // Action Buttons
            HStack {
                Button("取消") {
                    dismiss()
                }
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
                
                Button("儲存") {
                    let newTestMethod = "\(selectedDistance)_\(selectedDirection)"
                    
                    if packet.profileData != nil {
                        packet.profileData!.testMethod = newTestMethod
                    } else {
                        packet.profileData = ProfileData(phone_rssi: 0, testMethod: newTestMethod)
                    }
                    
                    dismiss()
                }
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
        }
        .padding(30)
    }
}
