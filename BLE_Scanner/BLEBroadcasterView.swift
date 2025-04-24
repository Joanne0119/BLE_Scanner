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
    @State private var inputMask = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("廣播端").font(.largeTitle).bold()
            Text("加總 13 byte")
            TextField("輸入遮罩 (十六進位)", text: $inputMask)
                .keyboardType(.asciiCapable)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .id("MaskBroadcast")
            
            TextField("輸入裝置 ID (十六進位)", text: $inputID)
                .keyboardType(.asciiCapable)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .id("IdBroadcast")
            
            TextField("輸入廣播內容 (十六進位)", text: $inputData)
                .keyboardType(.asciiCapable)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .id("DataBroadcast")

            Button("開始廣播") {
                
                // 解析遮罩
                guard let maskBytes = broadcaster.parseHexInput(inputMask) else {
                    alertMessage = "遮罩格式錯誤，請確保是有效的十六進位"
                    showAlert = true
                    return
                }
                
                // 解析ID (一個位元組)
                guard !inputID.isEmpty, let idByte = UInt8(inputID, radix: 16) else {
                    alertMessage = "ID 格式錯誤，請確保是有效的十六進位"
                    showAlert = true
                    return
                }
                
                // 解析自定義資料
                guard let dataBytes = broadcaster.parseHexInput(inputData) else {
                    alertMessage = "廣播內容格式錯誤，請確保是有效的十六進位"
                    showAlert = true
                    return
                }
                
                // 計算總長度
                let totalLength = maskBytes.count + dataBytes.count + 1 // +1 for ID
                
                if totalLength > 13 {
                    alertMessage = "封包大小加總需小於等於 13 byte，目前為 \(totalLength) byte"
                    showAlert = true
                } else {
                    // 執行廣播
                    broadcaster.startAdvertising(mask: maskBytes, id: idByte, customData: dataBytes)
                }
            }
            .buttonStyle(.borderedProminent)
            .alert(alertMessage, isPresented: $showAlert) {
                Button("知道了", role: .cancel) { }
            }
            
            Button("停止廣播"){
                if(broadcaster.isAdvertising){
                    broadcaster.stopAdervtising()
                }
                else {
                    alertMessage = "請先開始廣播"
                    showAlert = true
                }
            }
            .buttonStyle(.borderedProminent)
            .alert(alertMessage, isPresented: $showAlert) {
                Button("知道了", role: .cancel) { }
            }

            if broadcaster.nameStr != "N/A" {
                Text("Payload: \(broadcaster.nameStr)")
                    .padding()
            }
        }
        .padding()
        
    }
}

#Preview {
    BLEBroadcasterView()
}
