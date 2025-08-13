//
//  ResultSummaryView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/8/13.
//
import SwiftUI

struct ResultsSummaryView: View {
    @EnvironmentObject var savedPacketsStore: SavedPacketsStore

    var body: some View {
        NavigationView {
            List(savedPacketsStore.packets) { packet in
                VStack(alignment: .leading) {
                    Text("測試方法: \(packet.profileData?.testMethod ?? "N/A")")
                        .font(.headline)
                    // 安全地解包可選值來顯示結果
                    if let avgTx = packet.profileData?.avgTx, let avgRx = packet.profileData?.avgRx {
                        Text(String(format: "Avg Tx: %.1f dBm", avgTx))
                        Text(String(format: "Avg Rx: %.1f dBm", avgRx))
                    } else {
                        Text("尚未執行")
                            .foregroundColor(.gray)
                    }
                    Text("測試組ID: \(packet.testGroupID ?? "N/A")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("所有測試結果")
        }
    }
}
