//
//  DeviceProfileHistoryView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/8/13.
// 最後更新 2025/08/14

import SwiftUI

// MARK: - 主視圖 (Main View)
struct DeviceProfileHistoryView: View {
    @EnvironmentObject var packetStore: SavedPacketsStore
    let deviceID: String

    private var testGroups: [String] {
        let allPacketsForDevice = packetStore.packets.filter { $0.deviceID == self.deviceID && $0.profileData != nil }
        let groupIDs = Set(allPacketsForDevice.compactMap { $0.testGroupID })
        return Array(groupIDs).sorted(by: >)
    }
    
    var body: some View {
        NavigationView {
            if testGroups.isEmpty {
                Text("此節點 (\(deviceID)) 沒有任何 Profile 紀錄")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(testGroups, id: \.self) { groupID in
                            TestGroupSectionView(
                                testGroupID: groupID,
                                packets: packetStore.packets.filter { $0.testGroupID == groupID }
                            )
                        }
                    }
                    .padding()
                }
                .navigationTitle("\(deviceID)'s Profile History")
            }
        }
    }
}

// MARK: - Test Group Section
struct TestGroupSectionView: View {
    let testGroupID: String
    let packets: [BLEPacket]
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private var sortedPackets: [BLEPacket] {
        packets.sorted {
            guard let method1 = $0.profileData?.testMethod, let method2 = $1.profileData?.testMethod else {
                return false
            }
            return method1 < method2
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(testGroupID)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.bottom, 8)
            .border(width: 1, edges: [.bottom], color: .gray.opacity(0.3))

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(sortedPackets) { packet in
                    ProfileResultCard(packet: packet)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Result Card
struct ProfileResultCard: View {
    let packet: BLEPacket
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(packet.profileData?.testMethod ?? "N/A")
                .font(.headline)
                .foregroundColor(.primary)

            if let avgTx = packet.profileData?.avgTx, let avgRx = packet.profileData?.avgRx { //
                VStack(alignment: .leading) {
                    Text(String(format: "Tx: %.1f", avgTx))
                    Text(String(format: "Rx: %.1f", avgRx))
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.blue)
            } else {
                Text("未執行")
                    .font(.body)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}


// MARK: - Helper for Border
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return self.width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return self.width
                case .leading, .trailing: return rect.height
                }
            }
            path.addPath(Path(CGRect(x: x, y: y, width: w, height: h)))
        }
        return path
    }
}
