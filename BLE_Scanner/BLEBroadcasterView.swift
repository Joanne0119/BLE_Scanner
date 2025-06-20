//
//  BLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/06/20
//

import SwiftUI
import AVFoundation
import UIKit

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
    @State private var isExpanded: Bool = false
    
    @Binding var maskSuggestions: [String]
    @Binding var dataSuggestions: [String]
    
    @State private var maskError: String?
    @State private var dataError: String?
    @State private var idError: String?

    
    var body: some View {
        ZStack {
            Color.white.opacity(0.01)
                .onTapGesture {
                    if focusedField != nil{
                        focusedField = nil
                    }
                    if isExpanded {
                        withAnimation {
                            isExpanded = false
                        }
                    }
                }
            VStack(spacing: 20) {
                Text("廣播端").font(.largeTitle).bold()
                DisclosureGroup(
                    isExpanded: $isExpanded.animation(.easeInOut(duration: 0.3)),
                    content: {
                        VStack(alignment: .center) {
                            Text("請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                                .font(.system(size: 15, weight: .light, design: .serif))
                                .padding(.vertical)
                            Text("封包格式 = 遮罩 ＋ 內容 ＋ ID")
                                .font(.system(size: 18, weight: .bold))
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(20)
                        }
                        
                    }, label: {
                        Text("說明")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                )
                .padding()
                HStack {
                    if let error = combinedError  {
                        Text(error)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    else {
                        Text("\(currentByte) byte")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    
                    Text("/ 26 byte")
                        .font(.system(size: 20, weight: .bold))
                }
                
//MARK: - 遮罩輸入
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("遮罩：")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .frame(width: 60, alignment: .leading)
                            ZStack {
                                HStack {
                                    TextField("ex: 7A 00 01", text: $inputMask)
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                        .keyboardType(.asciiCapable)
                                        .padding(.horizontal)
                                        .id("MaskBroadcast")
                                        .focused($focusedField, equals: .mask)
                                        .onChange(of: inputMask) { newValue in
                                            enforceMaxLength(
                                                originalInput: newValue,
                                                input: &inputMask,
                                                otherInputs: [inputData, inputID],
                                                parseHex: broadcaster.parseHexInput,
                                                updateByteCount: updateByteCount
                                            )
                                            validateField(
                                                originalInput: newValue,
                                                errorBinding: &maskError,
                                                fieldName: "遮罩",
                                                parseHex: broadcaster.parseHexInput,
                                                isAsciiSafe: broadcaster.isAsciiSafe) { corrected in
                                                    inputMask = corrected
                                                }
                                        }
                                        .padding(.vertical)
                                    
                                    // 清除按鈕
                                    if !inputMask.isEmpty {
                                        Button(action: {
                                            inputMask = ""
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.trailing, 12)
                                        .transition(.opacity)
                                    }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(maskError == nil ? Color.secondary : Color.red, lineWidth: 2)
                            )
                        }
                        if focusedField == .mask {
                            HStack {
                                Spacer()
                                    .frame(width: 80, alignment: .leading)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        if maskSuggestions.filter({ !$0.isEmpty }).isEmpty {
                                            Text("沒有自訂遮罩！").foregroundColor(.black)
                                        } else{
                                            ForEach(maskSuggestions, id: \.self) { suggestion in
                                                Button(action: {
                                                    inputMask = suggestion
                                                    updateByteCount()
                                                    focusedField = nil // 選擇後取消焦點
                                                }) {
                                                    Text(suggestion)
                                                        .padding(.vertical, 5)
                                                        .padding(.horizontal, 10)
                                                        .background(Color.blue.opacity(0.2))
                                                        .foregroundColor(.primary)
                                                        .cornerRadius(8)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    }
                                    .padding(8)
                                }
                                .padding(5)
                                .frame(height: 40)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .padding(.bottom)
                        }
                    }
//MARK: - 內容輸入
                    VStack(alignment: .leading){
                        HStack {
                            Text("內容：")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .frame(width: 60, alignment: .leading)
                            ZStack(){
                                HStack(){
                                    TextField("ex: 01 ,03 0564, 10", text: $inputData)
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                        .keyboardType(.asciiCapable)
                                        .padding(.horizontal)
                                        .id("DataBroadcast")
                                        .focused($focusedField, equals: .data)
                                        .onChange(of: inputData) { newValue in
                                            enforceMaxLength(
                                                originalInput: newValue,
                                                input: &inputData,
                                                otherInputs: [inputMask, inputID],
                                                parseHex: broadcaster.parseHexInput,
                                                updateByteCount: updateByteCount
                                            )
                                            validateField(
                                                originalInput:  newValue,
                                                errorBinding: &dataError,
                                                fieldName: "內容",
                                                parseHex: broadcaster.parseHexInput,
                                                isAsciiSafe: broadcaster.isAsciiSafe){ corrected in
                                                    inputData = corrected
                                                }
                                        }
                                        .padding(.vertical)
                                    if !inputData.isEmpty {
                                        Button(action: {
                                            inputData = ""
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.trailing, 12)
                                        .transition(.opacity)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(dataError == nil ? Color.secondary : Color.red, lineWidth: 2)
                                )
                            }
                            
                        }
                        if focusedField == .data {
                                HStack {
                                    Spacer()
                                        .frame(width: 80, alignment: .leading)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            if dataSuggestions.filter({ !$0.isEmpty }).isEmpty {
                                                Text("沒有自訂內容！").foregroundColor(.black)
                                            }
                                            else{
                                                ForEach(dataSuggestions, id: \.self) { suggestion in
                                                    Button(action: {
                                                        inputData = suggestion
                                                        updateByteCount()
                                                        focusedField = nil // 選擇後取消焦點
                                                    }) {
                                                        Text(suggestion)
                                                            .padding(.vertical, 5)
                                                            .padding(.horizontal, 10)
                                                            .background(Color.blue.opacity(0.2))
                                                            .foregroundColor(.primary)
                                                            .cornerRadius(8)
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                }
                                            }
                                        }
                                        .padding(8)
                                    }
                                    .padding(5)
                                    .frame(height: 40)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .padding(.bottom)
                            }
                    }
//MARK: - ID輸入
                    HStack {
                        Text("ID：")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .frame(width: 60, alignment: .leading)
                        ZStack(){
                            HStack(){
                                TextField("ex: 01", text: $inputID)
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                                    .keyboardType(.asciiCapable)
                                    .padding(.horizontal)
                                    .id("IdBroadcast")
                                    .focused($focusedField, equals: .id)
                                    .onChange(of: inputID) { newValue in
                                        enforceMaxLength(
                                            originalInput: newValue,
                                            input: &inputID,
                                            otherInputs: [inputMask, inputData],
                                            parseHex: broadcaster.parseHexInput,
                                            updateByteCount: updateByteCount
                                        )
                                        validateField(
                                            originalInput: newValue,
                                            errorBinding: &idError,
                                            fieldName: "ID",
                                            parseHex: broadcaster.parseHexInput,
                                            isAsciiSafe: broadcaster.isAsciiSafe){ corrected in
                                                inputID = corrected
                                            }
                                    }
                                    .padding(.vertical)
                                if !inputID.isEmpty {
                                    Button(action: {
                                        inputID = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.trailing, 12)
                                    .transition(.opacity)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(idError == nil ? Color.secondary : Color.red, lineWidth: 2)
                            )
                        }
                        
                    }
                }
                .padding()
//MARK: - 按鈕
                HStack {
                    Button(broadcaster.isRepeatAdv ? "停止廣播" : "開始廣播") {
                        if broadcaster.isRepeatAdv {
                            broadcaster.stopRepeatingAdvertising()
                            print("isAdv: \(broadcaster.isRepeatAdv)")
                        } else {
                            // 解析遮罩
                            guard let maskBytes = broadcaster.parseHexInput(inputMask) else { return }
                            // 解析ID (一個位元組)
                            guard let idByte = broadcaster.parseHexInput(inputID) else { return }
                            // 解析自定義資料
                            guard let dataBytes = broadcaster.parseHexInput(inputData) else { return }
                            // 執行廣播
                            broadcaster.startRepeatingAdvertising(mask: maskBytes, id: idByte, customData: dataBytes)
                            print("isAdv: \(broadcaster.isAdvertising)")
                        }
                    }
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .buttonStyle(.borderedProminent)
                    .tint(broadcaster.isRepeatAdv ? .red : .blue)
                    .alert(alertMessage, isPresented: $showAlert) {
                        Button("知道了", role: .cancel) { }
                    }
                    .disabled((!broadcaster.isRepeatAdv) && (maskError != nil || dataError != nil || idError != nil))
                }
                
                if broadcaster.nameStr != "N/A" && broadcaster.isRepeatAdv{
                    Text("廣播中...")
                        .font(.system(size: 15, weight: .light, design: .serif))
                    Text("Payload: \(broadcaster.nameStr)")
                        .font(.system(size: 15, weight: .light, design: .serif))
                        .foregroundStyle(.primary)
                        .padding(.bottom)
                        .padding(.top, 6)
                }
                else {
                    Text("Ex: Payload: 7A000101030F3E0001")
                        .font(.system(size: 15, weight: .light, design: .serif))
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

//MARK: - 格式錯誤檢查
    func validateField(
        originalInput: String,
        errorBinding: inout String?,
        fieldName: String,
        parseHex: (String) -> [UInt8]?,
        isAsciiSafe: ([UInt8]) -> Bool,
        setInput: @escaping (String) -> Void
    ) {
        print("使用者輸入原始值：\(originalInput)")

        let cleanedHex = originalInput.cleanedHex
        guard let bytes = parseHex(cleanedHex) else {
            errorBinding = "\(fieldName)格式錯誤"
            return
        }

        if !isAsciiSafe(bytes) {
            errorBinding = "\(fieldName)應在 01~7F 內"
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1102)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 保留格式，只刪掉最後兩個字元（避免跳動感太重）
                let trimmed = String(originalInput.dropLast(2))
                setInput(trimmed)
            }

        } else if bytes.contains(0x00) {
            errorBinding = "\(fieldName)不能包含 00"
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1102)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let trimmed = String(originalInput.dropLast(2))
                setInput(trimmed)
            }

        } else {
            errorBinding = nil
        }
    }
    
    func updateByteCount() {
        let mask = broadcaster.parseHexInput(inputMask) ?? []
        let data = broadcaster.parseHexInput(inputData) ?? []
        let id = broadcaster.parseHexInput(inputID) ?? []
        currentByte = mask.count + data.count + id.count
    }
    
    var combinedError: String? {
        if let maskError = maskError {
            return maskError
        }
        if let dataError = dataError {
            return dataError
        }
        if let idError = idError {
            return idError
        }
        return nil
    }
    
    func enforceMaxLength(
        originalInput: String,
        input: inout String,
        otherInputs: [String],
        parseHex: (String) -> [UInt8]?,
        updateByteCount: () -> Void
    ) {
        let cleanedHex = originalInput.cleanedHex
        guard let inputBytes = parseHex(cleanedHex) else {
            return
        }

        let otherBytesCount = otherInputs
            .compactMap { parseHex($0.cleanedHex)?.count }
            .reduce(0, +)

        let totalBytes = otherBytesCount + inputBytes.count

        if totalBytes > 26 {
            // 超過最大長度，刪掉原始輸入尾端兩個字元（不破壞空白或逗號格式）
            input = String(originalInput.dropLast(2))
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1103)
        } else {
            input = originalInput
        }

        updateByteCount()
    }


    private func hideKeyboard() {
       UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
   }
    
    func triggerInputLimitFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

