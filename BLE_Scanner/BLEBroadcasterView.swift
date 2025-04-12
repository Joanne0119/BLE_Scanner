//
//  BLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//

import SwiftUI

struct BLEBroadcasterView: View {
    @StateObject private var broadcaster = CBLEBroadcaster()
    @State private var inputID = ""
    @State private var inputData = ""
    

    var body: some View {
        VStack(spacing: 20) {
            Text("廣播端").font(.largeTitle).bold()
            
            TextField("輸入裝置 ID (十六進位)", text: $inputID)
                .keyboardType(.asciiCapable)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextField("輸入廣播內容 (十六進位，用空格分隔)", text: $inputData)
                .keyboardType(.asciiCapable)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("開始廣播") {
                if let idByte = UInt8(inputID, radix: 16),
                    let dataByte = broadcaster.parseHexInput(inputData)
                {
                    broadcaster.startAdvertising(id: idByte, customData: dataByte)
                }
            }
            .buttonStyle(.borderedProminent)

            if broadcaster.currentPayload != "N/A" {
                Text("Payload: \(broadcaster.currentPayload)")
                    .padding()
            }
        }
        .padding()
        
    }
}

#Preview {
    BLEBroadcasterView()
}
