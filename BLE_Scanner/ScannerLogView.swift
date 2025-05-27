//
//  ScannerLogView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/5/27.
//

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
        ZStack {
            Color.white.opacity(0.01)
                .onTapGesture {
                    if focusState != false{
                        focusState = false
                    }
                }
            VStack(spacing: 20) {
                Text("掃描Log")
                    .font(.largeTitle).bold()
                DisclosureGroup(
                    isExpanded: $isExpanded,
                    content: {
                            HStack {
                                Text("ID： ")
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                                TextField("ex：01", text: $idText)
                                    .font(.system(size: 18, weight: .bold, design: .serif))
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
                                .font(.system(size: 18, weight: .bold, design: .serif))
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ID：\(packet.deviceID)")
                                Text("RSSI：\(packet.rssi) dBm")
                                Text("Mask：\(packet.mask)")
                                Text("Data：\(packet.data)")
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
            .padding()
        }
        .onAppear {
            loadSavedPackets()
        }
        .onReceive(NotificationCenter.default.publisher(for: .packetsUpdated)) { _ in
            loadSavedPackets()
        }
        
    }
    private func loadSavedPackets() {
        packetStore.reload()
    }
}
extension Notification.Name {
    static let packetsUpdated = Notification.Name("packetsUpdated")
}

