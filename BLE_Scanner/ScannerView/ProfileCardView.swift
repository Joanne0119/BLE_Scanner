//
//  ProfileCardView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/8/13.
//
import SwiftUI

struct ProfileCardView: View {
    @ObservedObject var scanner: CBLEScanner
    let deviceID: String
    @Binding var packet: BLEPacket
    
    let onEdit: (String) -> Void
    @State private var showRestartAlert = false
    
    private var isExecuting: Bool {
        scanner.averagingPacketID == packet.id
    }
    
    private var result: (tx: Double, rx: Double)? {
        if let profileData = packet.profileData,
           let tx = profileData.avgTx,
           let rx = profileData.avgRx {
            return (tx, rx)
        }
        return nil
    }
    
    
    // Timer that fires every second
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var runningTime: Int = 0

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if isExecuting {
                        Text("執行中...")
                            .font(.caption)
                    } else if result != nil {
                        Text("執行完畢")
                            .font(.caption)
                    }
                    Spacer()
                    Button(action: { onEdit(packet.id) }) {
                        HStack {
                            Text(packet.profileData?.testMethod ?? "未設定")
                                .font(.system(size: 20, weight: .medium)).underline()
                            Image(systemName: "pencil").font(.system(size: 18))
                        }
                    }.disabled(isExecuting)
                }
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        // 根據狀態顯示不同的值
                        Text("Tx: \(txValue) dBm")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Rx: \(rxValue) dBm")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button(action: handleButtonTap) {
                        Text(buttonText)
                            .font(.system(size: 20, weight: .medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .cornerRadius(10)
                    .disabled(isExecuting)
                }
            }
            .padding()
            .background(cardBackgroundColor)
            .cornerRadius(15)
            .padding(.horizontal)
            .foregroundColor(cardForegroundColor)
            .alert("重新執行", isPresented: $showRestartAlert) {
                Button("取消", role: .cancel) {}
                Button("確定", role: .destructive) {
                    startExecution()
                }
            } message: {
                Text("確定要清除這次的平均數據並重新執行嗎？")
            }
        }
    func handleButtonTap() {
        if result != nil { // 如果已完成，顯示警告
            showRestartAlert = true
        } else { // 否則，直接開始
            startExecution()
        }
    }
    
    func startExecution() {
        scanner.startAveragingRSSI(for: packet.id, deviceID: self.deviceID) { avgTx, avgRx, txs, rxs in
            print("executed with \(avgTx), \(avgRx), \(txs), \(rxs)")
        }
    }
    
    // --- Computed UI Properties ---
    
    var txValue: String {
        if isExecuting {
            return "\(scanner.matchedPackets[deviceID]?.rssi ?? 0)"
        } else if let res = result {
            return String(format: "%.1f", res.tx)
        } else {
            return "-"
        }
    }
    
    var rxValue: String {
        if isExecuting {
            return "\(scanner.matchedPackets[deviceID]?.profileData?.phone_rssi ?? 0)"
        } else if let res = result {
            return String(format: "%.1f", res.rx)
        } else {
            return "-"
        }
    }
    
    var buttonText: String {
        if isExecuting { return "執行中..." }
        if result != nil { return "重新執行" }
        return "開始執行"
    }
    
    var cardBackgroundColor: Color {
        if isExecuting { return .green }
        if result != nil { return .cyan.opacity(0.7) }
        return Color(UIColor.systemGray4)
    }
    
    var cardForegroundColor: Color {
        isExecuting || result != nil ? .white : .primary
    }
}
