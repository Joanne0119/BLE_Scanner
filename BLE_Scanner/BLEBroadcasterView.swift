//
//  BLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後建立 2025/5/02
//

import SwiftUI

struct BLEBroadcasterView: View {
    @StateObject private var broadcaster = CBLEBroadcaster()
    @State private var inputID = ""
    @State private var inputData = ""
    @State private var inputMask = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var buttonDisabled = false

    var body: some View {
        VStack(spacing: 20) {
            Text("廣播端").font(.largeTitle).bold()
            Text("請輸入 00 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: AA BB, CC）\n也可以不隔開（ex: AABBCC）")
                .font(.system(size: 12, weight: .light, design: .serif))
                .multilineTextAlignment(.center)
            Text("加總 26 byte")
            VStack {
                HStack {
                    Text("遮罩：")
                    TextField("ex: 7A 00 01", text: $inputMask)
                        .keyboardType(.asciiCapable)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .id("MaskBroadcast")
                }
                HStack {
                    Text("ID：")
                    TextField("ex: 01", text: $inputID)
                        .keyboardType(.asciiCapable)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .id("IdBroadcast")
                }
                HStack {
                    Text("內容：")
                    TextField("ex: 01 ,03 0F3E, 00", text: $inputData)
                        .keyboardType(.asciiCapable)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .id("DataBroadcast")
                }
            }
            .padding()
            HStack{
                Button("開始廣播") {
                    
                    // 解析遮罩
                    guard let maskBytes = broadcaster.parseHexInput(inputMask) else {
                        alertMessage = "遮罩格式錯誤，請確保是有效的十六進位"
                        showAlert = true
                        return
                    }
                    
                    if(!broadcaster.isAsciiSafe(maskBytes)){
                        alertMessage = "遮罩格式錯誤，請確保是介於00至7F之間的有效十六進位"
                        showAlert = true
                        return
                    }
                    
                    
                    // 解析ID (一個位元組)
                    guard let idByte = broadcaster.parseHexInput(inputID) else {
                        alertMessage = "ID 格式錯誤，請確保是有效的十六進位"
                        showAlert = true
                        return
                    }
                    
                    if(!broadcaster.isAsciiSafe(idByte)){
                        alertMessage = "ID格式錯誤，請確保是介於00至7F之間的有效十六進位"
                        showAlert = true
                        return
                    }
                    
                    // 解析自定義資料
                    guard let dataBytes = broadcaster.parseHexInput(inputData) else {
                        alertMessage = "廣播內容格式錯誤，請確保是有效的十六進位"
                        showAlert = true
                        return
                    }
                    
                    if(!broadcaster.isAsciiSafe(dataBytes)) {
                        alertMessage = "廣播內容格式錯誤，請確保是介於00至7F之間的有效十六進位"
                        showAlert = true
                        return
                    }
                    
                    if(maskBytes.first == 0x00){
                        alertMessage = "遮罩第一個值為0x00，很有可能會導致封包遺失！建議更改為其他值！"
                        showAlert = true
                        return
                    }
                    
                    // 計算總長度
                    let totalLength = maskBytes.count + dataBytes.count + idByte.count 
                    
                    if totalLength > 26 {
                        alertMessage = "封包大小加總需小於等於 26 byte，目前為 \(totalLength) byte"
                        showAlert = true
                    } else {
                        // 執行廣播
                        broadcaster.startAdvertising(mask: maskBytes, id: idByte, customData: dataBytes)
                    }
                    print("isAdv: \(broadcaster.isAdvertising)")
                }
                .buttonStyle(.borderedProminent)
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("知道了", role: .cancel) { }
                }
                .disabled(broadcaster.isAdvertising)
                
                Button("停止廣播"){
                    if(broadcaster.isAdvertising){
                        broadcaster.stopAdervtising()
                    }
                    else {
                        alertMessage = "請先開始廣播"
                        showAlert = true
                    }
                    print("isAdv: \(broadcaster.isAdvertising)")
                }
                .buttonStyle(.borderedProminent)
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("知道了", role: .cancel) { }
                }
                .disabled(!broadcaster.isAdvertising)
            }

            if broadcaster.nameStr != "N/A" {
                Text("Payload: \(broadcaster.nameStr)")
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .foregroundStyle(.primary)
                    .padding()
            }
            else {
                Text("Ex: Payload: 7A000101030F3E0001")
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        
    }
}

#Preview {
    BLEBroadcasterView()
}
