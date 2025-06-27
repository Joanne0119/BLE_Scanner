//
//  ScannerLogView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//  最後更新 2025/06/27

import SwiftUI
import Foundation

struct ScannerLogView: View {
    @FocusState private var focusState: Bool
    @State private var isExpanded: Bool = false
    @State private var idText: String = ""
    @ObservedObject var packetStore: SavedPacketsStore
    
    var filteredPackets: [BLEPacket] {
        if idText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return packetStore.packets
        } else {
            return packetStore.packets.filter { $0.deviceID.localizedCaseInsensitiveContains(idText) }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.opacity(0.01)
                    .onTapGesture {
                        if focusState != false{
                            focusState = false
                        }
                    }
                VStack(spacing: 20) {
                    DisclosureGroup(
                        isExpanded: $isExpanded,
                        content: {
                            HStack {
                                Text("ID： ")
                                    .font(.system(size: 18, weight: .bold))
                                TextField("ex：01", text: $idText)
                                    .font(.system(size: 18, weight: .bold))
                                    .id("IdScanner")
                                    .focused($focusState)
                                    .padding()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.secondary, lineWidth: 2)
                                    )
                            }
                            .padding()
                            
                        }, label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("篩選")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .font(.system(size: 17, weight: .bold))
                        }
                        
                    )
                    .padding()
                    if packetStore.packets.isEmpty {
                        Text("尚未儲存任何資料")
                            .foregroundColor(.gray)
                    } else {
                        List(filteredPackets) { packet in
                            VStack(alignment: .leading, spacing: 4) {
                                if let parsedData = packet.parsedData {
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ID：\(packet.deviceID)")
                                            .font(.system(size: 16, weight: .regular))
                                        Text("RSSI：\(packet.rssi) dBm")
                                            .font(.system(size: 16, weight: .regular))
                                        Text("Timestamp：\(formatTime(packet.timestamp))")
                                            .font(.system(size: 16, weight: .regular))
                                        HStack {
                                            Text("⏱️ 時間：\(parsedData.seconds) 秒")
                                                .font(.system(size: 15, weight: .medium))
                                            Spacer()
                                            if parsedData.hasReachedTarget {
                                                Text("已達標")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.green)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.2))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        
                                        Text("🌡️ 溫度：\(parsedData.temperature) °C")
                                            .font(.system(size: 15, weight: .medium))
                                        
                                        Text("🎚️ 大氣壓力：\(String(format: "%.2f", parsedData.atmosphericPressure)) hPa")
                                            .font(.system(size: 15, weight: .medium))
                                        
                                        
                                        Text("📱 裝置接收狀況：")
                                            .font(.system(size: 15, weight: .medium))
                                            .padding(.top, 4)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(Array(parsedData.devices.enumerated()), id: \.offset) { index, device in
                                                HStack {
                                                    
                                                    Text("ID: \(device.deviceId)")
                                                        .font(.system(size: 14, weight: .regular))
                                                        .frame(width: 50, alignment: .leading)
                                                    
                                                    Text("次數: \(device.count)")
                                                        .font(.system(size: 14, weight: .regular))
                                                        .frame(width: 60, alignment: .leading)
                                                    
                                                    Spacer()
                                                    
                                                    Text("\(String(format: "%.1f", device.receptionRate)) 次/秒")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(device.count >= 100 ? .green : .primary)
                                                }
                                            }
                                        }
                                        .padding(.leading, 8)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding()
                            .cornerRadius(8)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    packetStore.delete(packet)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
                .navigationTitle("掃描Log")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        MQTTToolbarStatusView()
                    }
                }
                .padding()
            }
            .onAppear {
                loadSavedPackets()
            }
            .onReceive(NotificationCenter.default.publisher(for: .packetsUpdated)) { _ in
                loadSavedPackets()
            }
        }
        .navigationBarHidden(false)
        
    }
    private func loadSavedPackets() {
        packetStore.reload()
    }
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
extension Notification.Name {
    static let packetsUpdated = Notification.Name("packetsUpdated")
}

