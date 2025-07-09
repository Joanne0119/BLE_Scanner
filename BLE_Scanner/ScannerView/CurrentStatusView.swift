//
//  CurrentStatusView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//

import SwiftUI

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
        .background(Color(.gray).opacity(0.2))
        .cornerRadius(10)
    }
}
