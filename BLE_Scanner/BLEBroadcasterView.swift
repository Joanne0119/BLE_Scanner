//
//  BLEBroadcaster.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/06/27
//  最後更新 2025/07/07

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
        NavigationView {
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
                ScrollView {
                    
                    topInfoSection
                    
                    // MARK: -輸入區塊
                    VStack(alignment: .leading) {
                        // 遮罩輸入區塊
                        BroadcastInputSectionView(
                            title: "遮罩：",
                            placeholder: "ex: 7A 00 01",
                            text: $inputMask,
                            error: $maskError,
                            focusedField: $focusedField,
                            fieldCase: .mask,
                            suggestions: maskSuggestions,
                            onInputChange: { validateMask() },
                            onSuggestionTap: { suggestion in
                                handleSuggestionTap(for: .mask, suggestion: suggestion)
                            }
                        )
                        
                        // 內容輸入區塊
                        BroadcastInputSectionView(
                            title: "內容：",
                            placeholder: "ex: 01 ,03 0564, 10",
                            text: $inputData,
                            error: $dataError,
                            focusedField: $focusedField,
                            fieldCase: .data,
                            suggestions: dataSuggestions,
                            onInputChange: { validateData() },
                            onSuggestionTap: { suggestion in
                                handleSuggestionTap(for: .data, suggestion: suggestion)
                            }
                        )
                        
                        // ID 輸入區塊 (沒有 suggestions)
                        BroadcastInputSectionView(
                            title: "ID：",
                            placeholder: "ex: 01",
                            text: $inputID,
                            error: $idError,
                            focusedField: $focusedField,
                            fieldCase: .id,
                            suggestions: nil, // 傳入 nil
                            onInputChange: { validateID() },
                            onSuggestionTap: { _ in } // 不需要操作
                        )

                    }
                    .padding()
                    
                    actionButtonSection
                    
                    if broadcaster.nameStr != "N/A" && broadcaster.isRepeatAdv{
                        Text("廣播中...")
                            .font(.system(size: 15, weight: .light))
                        Text("Payload: \(broadcaster.nameStr)")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.primary)
                            .padding(.bottom)
                            .padding(.top, 6)
                    }
                    else {
                        Text("Ex: Payload: 7A000101030F3E0001")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .navigationTitle("廣播端")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        MQTTToolbarStatusView()
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
        .navigationBarHidden(false)
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var topInfoSection: some View {
        ZStack {
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
            
            HStack {
            Spacer()
                HelpButtonView {
                    
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .center) {
                            Text("封包格式 = 遮罩 ＋ 內容 ＋ ID")
                                .font(.system(size: 25, weight: .bold))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                        Text("廣播端的封包請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                            .font(.system(size: 20, weight: .medium))
                            
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
    
    //MARK: - 按鈕
    private var actionButtonSection: some View {
        VStack {
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
            .font(.system(size: 20, weight: .medium))
            .buttonStyle(.borderedProminent)
            .tint(broadcaster.isRepeatAdv ? .red : .blue)
            .alert(alertMessage, isPresented: $showAlert) {
                Button("知道了", role: .cancel) { }
            }
            .disabled(maskError != nil || dataError != nil || idError != nil)
            Text("\n快速廣播")
                .font(.system(size: 20, weight: .medium))
            HStack {
                Button("重設") {
                    inputMask = "7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F"
                    inputData = "7F"
                    inputID = "7F"
                    broadcaster.startRepeatingAdvertising(mask: [0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F], id: [0x7F], customData: [0x7F])
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .font(.system(size: 20, weight: .medium))
                .disabled(broadcaster.isRepeatAdv)
                
                Button("重啟") {
                    inputMask = "7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F7F"
                    inputData = "7F"
                    inputID = "7E"
                    broadcaster.startRepeatingAdvertising(mask: [0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F], id: [0x7E], customData: [0x7F])
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .font(.system(size: 20, weight: .medium))
                .disabled(broadcaster.isRepeatAdv)
            }
        }
    }

    //MARK: - Helper Function
    private func dismissKeyboardAndSuggestions() {
            if focusedField != nil {
                focusedField = nil
            }
            if isExpanded {
                withAnimation {
                    isExpanded = false
                }
            }
            hideKeyboard()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        
        private func handleSuggestionTap(for field: Field, suggestion: String) {
            switch field {
            case .mask:
                inputMask = suggestion
            case .data:
                inputData = suggestion
            case .id:
                inputID = suggestion
            }
            updateByteCount()
            focusedField = nil
        }

        // MARK: - Validation Logic (保持不變, 但現在由各自的閉包觸發)

    func validateMask() {
        enforceMaxLength(
            originalInput: inputMask,
            input: &inputMask,
            otherInputs: [inputData, inputID],
            parseHex: broadcaster.parseHexInput,
            updateByteCount: updateByteCount
        )
        validateField(
            originalInput: inputMask,
            errorBinding: &maskError,
            fieldName: "遮罩",
            parseHex: broadcaster.parseHexInput,
            isAsciiSafe: broadcaster.isAsciiSafe,
            setInput: { corrected in inputMask = corrected }
        )
    }

    func validateData() {
        enforceMaxLength(
            originalInput: inputData,
            input: &inputData,
            otherInputs: [inputMask, inputID],
            parseHex: broadcaster.parseHexInput,
            updateByteCount: updateByteCount
        )
        validateField(
            originalInput: inputData,
            errorBinding: &dataError,
            fieldName: "內容",
            parseHex: broadcaster.parseHexInput,
            isAsciiSafe: broadcaster.isAsciiSafe,
            setInput: { corrected in inputData = corrected }
        )
    }

    func validateID() {
        enforceMaxLength(
            originalInput: inputID,
            input: &inputID,
            otherInputs: [inputMask, inputData],
            parseHex: broadcaster.parseHexInput,
            updateByteCount: updateByteCount
        )
        validateField(
            originalInput: inputID,
            errorBinding: &idError,
            fieldName: "ID",
            parseHex: broadcaster.parseHexInput,
            isAsciiSafe: broadcaster.isAsciiSafe,
            setInput: { corrected in inputID = corrected }
        )
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


struct SuggestionsView: View {
    let suggestions: [String]
    let onSuggestionTap: (String) -> Void
    
    var body: some View {
        HStack {
            // 用於對齊左側的標題
            Spacer().frame(width: 80)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if suggestions.filter({ !$0.isEmpty }).isEmpty {
                        Text("沒有自訂建議！")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                onSuggestionTap(suggestion)
                            }) {
                                Text(suggestion)
                                    .font(.system(size: 16, weight: .medium))
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .frame(minWidth: 50, minHeight: 40)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: 60)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.bottom)
    }
}

struct BroadcastInputSectionView: View {
    let title: String
    let placeholder: String
    
    // 從父視圖綁定狀態
    @Binding var text: String
    @Binding var error: String?
    
    // 焦點狀態也從父視圖傳入
    @FocusState.Binding var focusedField: BLEBroadcasterView.Field?
    
    // 用於判斷焦點和顯示建議
    let fieldCase: BLEBroadcasterView.Field
    let suggestions: [String]? // ID 輸入框沒有建議，所以設為可選
    
    // 將操作回傳給父視圖處理
    let onInputChange: () -> Void
    let onSuggestionTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 60, alignment: .leading)
                
                ZStack {
                    HStack {
                        TextField(placeholder, text: $text)
                            .font(.system(size: 18, weight: .bold))
                            .keyboardType(.asciiCapable)
                            .padding(.horizontal)
                            .focused($focusedField, equals: fieldCase)
                            .onChange(of: text) { _ in
                                // 當文字改變時，通知父視圖去執行驗證邏輯
                                onInputChange()
                            }
                            .padding(.vertical)
                        
                        // 清除按鈕
                        if !text.isEmpty {
                            Button(action: {
                                text = ""
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
                        .stroke(error == nil ? Color.secondary : Color.red, lineWidth: 2)
                )
            }
            
            // 如果此輸入框處於焦點，並且有建議內容，則顯示建議列表
            if focusedField == fieldCase, let suggestions = suggestions {
                SuggestionsView(suggestions: suggestions, onSuggestionTap: onSuggestionTap)
            }
        }
    }
}
