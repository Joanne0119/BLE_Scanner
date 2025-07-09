//
//  BLEWatchScannerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//

import SwiftUI

struct BLEWatchScannerView: View {
    @StateObject private var scanner = CBLEScanner()
    var body: some View {
        Text("點擊一下來掃描")
    }
}

#Preview {
    BLEWatchScannerView()
}
