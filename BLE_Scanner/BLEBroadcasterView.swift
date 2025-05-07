//
//  BLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
// 最後更新 2025/05/07
//

import SwiftUI

struct BLEBroadcasterView: View {
    enum Field: Hashable {
        case mask
        case data
        case id
    }
    
    @StateObject private var broadcaster = CBLEBroadcaster()
    @State private var inputID = ""
    @State private var inputData = ""
    @State private var inputMask = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var buttonDisabled = false
    @State private var currentByte: Int = 0
    @FocusState private var focusedField: Field?
    
    var body: some View {
        ZStack {
            Color.white.opacity(0.01)
                .onTapGesture {
                    if focusedField != nil{
                        focusedField = nil
                    }
                }
            VStack(spacing: 20) {
                Text("廣播端").font(.largeTitle).bold()
                Text("請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .multilineTextAlignment(.center)
                Text("* 不要使用 00，可能會導致00後的資料遺失")
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .foregroundStyle(.red)
                Text("封包格式 = 遮罩 ＋ 內容 ＋ ID")
                    .font(.system(size: 20, weight: .bold))
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(20)
                HStack {
                    if inputID.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined().count % 2 != 0
                        || inputData.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined().count % 2 != 0
                        || inputMask.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined().count % 2 != 0 {
                        Text("輸入不完整")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    else {
                        Text("\(currentByte) byte")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    
                    Text("/ 26 byte")
                        .font(.system(size: 20, weight: .bold))
                }
                
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("遮罩：")
                        TextField("ex: 7A 00 01", text: $inputMask)
                            .keyboardType(.asciiCapable)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .id("MaskBroadcast")
                            .focused($focusedField, equals: .mask)
                            .onChange(of: inputMask) { _ in updateByteCount() }
                    }
                    .padding()
                    HStack {
                        Text("內容：")
                        TextField("ex: 01 ,03 0F3E, 00", text: $inputData)
                            .keyboardType(.asciiCapable)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .id("DataBroadcast")
                            .focused($focusedField, equals: .data)
                            .onChange(of: inputData) { _ in updateByteCount() }
                        
                        
                    }
                    .padding()
                    HStack {
                        Text("ID：")
                        TextField("ex: 01", text: $inputID)
                            .keyboardType(.asciiCapable)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .id("IdBroadcast")
                            .focused($focusedField, equals: .id)
                            .onChange(of: inputID) { _ in updateByteCount() }
                    }
                    .padding()
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
                        
                        if(maskBytes.contains(0x00) ){
                            alertMessage = "遮罩裡有 0x00，有可能會導致部分封包遺失！"
                            showAlert = true
                            return
                        }
                        if(idByte.contains(0x00) ){
                            alertMessage = "ID裡有 0x00，有可能會導致部分封包遺失！"
                            showAlert = true
                            return
                        }
                        if(dataBytes.contains(0x00) ){
                            alertMessage = "內容裡有 0x00，有可能會導致部分封包遺失！"
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
                
                if broadcaster.nameStr != "N/A" && broadcaster.isAdvertising{
                    Text("廣播中...")
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
            .onTapGesture {
                if focusedField != nil{
                    focusedField = nil
                }
            }
        }
        
    }

    
    func updateByteCount() {
        let mask = broadcaster.parseHexInput(inputMask) ?? []
        let data = broadcaster.parseHexInput(inputData) ?? []
        let id = broadcaster.parseHexInput(inputID) ?? []
        currentByte = mask.count + data.count + id.count
    }

    private func hideKeyboard() {
       UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
   }
}

#Preview {
    BLEBroadcasterView()
}
