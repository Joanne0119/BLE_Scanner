// 最後更新 2025/06/03

import SwiftUI
import AVFoundation
import UIKit

struct SettingView: View {
    enum SuggestionType: String, CaseIterable {
        case mask = "遮罩"
        case data = "內容"
    }

    @State private var selectedType: SuggestionType = .mask
    @State private var isExpanded: Bool = false
    @FocusState private var focusState: Bool

    @State private var maskInput = ""
    @State private var dataInput = ""

    @Binding var maskSuggestions: [String]
    @Binding var dataSuggestions: [String]
    @State private var maskError: String?
    @State private var dataError: String?
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var editingIndex: Int? = nil
    @State private var editingByteStatus: String = ""

    var body: some View {
        ZStack {
            Color.white.opacity(0.01)
                .onTapGesture {
                    if focusState != false{
                        focusState = false
                    }
                }
            VStack {
                Text("自訂輸入").font(.largeTitle).bold()
                
                Picker("選擇類型", selection: $selectedType) {
                    ForEach(SuggestionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .onChange(of: selectedType) { newType in
                    // 重新驗證當前選定類型的輸入內容
                    let currentInput = binding(for: newType).wrappedValue
                    validateField(
                        originalInput: currentInput,
                        errorBinding: &errorBinding(for: newType).wrappedValue,
                        fieldName: newType.rawValue,
                        parseHex: parseHexInput,
                        isAsciiSafe: isAsciiSafe
                    ) { corrected in
                        binding(for: newType).wrappedValue = corrected
                    }
                }
                
                DisclosureGroup(
                    isExpanded: $isExpanded,
                    content: {
                        HStack{
                            VStack(alignment: .leading) {
                                Text("自訂遮罩與內容的快速選取欄位，此自訂內容會出現在廣播與掃描端的輸入框下方")
                                    .font(.system(size: 15, weight: .light, design: .serif))
                                Text("請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                                    .font(.system(size: 15, weight: .light, design: .serif))
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(20)
                                Text("* 不要使用 00，可能會導致00後的資料遺失")
                                    .font(.system(size: 15, weight: .light, design: .serif))
                                    .foregroundStyle(.red)
                            }
                            .padding()
                            
                            Spacer()
                        }
                    }, label: {
                        Text("說明")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                )
                .padding()
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("目前Byte數: ")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                        
                        if let error = combinedError {
                            Text(error)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.red)
                        } else {
                            // 取得當前輸入，根據選擇的類型
                            let currentInput = binding(for: selectedType).wrappedValue
                            
                            // 當輸入為空時顯示 0 byte
                            if currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("0 byte")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                            } else {
                                if let bytes = parseHexInput(currentInput) {
                                    Text("\(bytes.count) byte")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("0 byte")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .padding()
                    
                    
                    Text("自訂\(selectedType.rawValue)")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal)
                    
                    HStack {
                        TextField("輸入自訂\(selectedType.rawValue)", text: binding(for: selectedType))
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .focused($focusState)
                            .onChange(of: binding(for: selectedType).wrappedValue) { newValue in
                                enforceMaxLength(
                                    originalInput: newValue,
                                    input: &binding(for: selectedType).wrappedValue,
                                    parseHex: parseHexInput
                                )
                                validateField(
                                    originalInput: newValue,
                                    errorBinding: &errorBinding(for: selectedType).wrappedValue,
                                    fieldName: selectedType.rawValue,
                                    parseHex: parseHexInput,
                                    isAsciiSafe: isAsciiSafe) { corrected in
                                        binding(for: selectedType).wrappedValue = corrected
                                }
                            }
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(combinedError == nil ? Color.secondary : Color.red, lineWidth: 2)
                            )
                        
                        Button("新增") {
                            addSuggestion(for: selectedType)
                        }
                        .font(.system(size: 18, weight: .bold, design: .serif))
                    }
                    .padding(.horizontal)
                }
                
                List {
                    ForEach(suggestions(for: selectedType), id: \.self) { suggestion in
                        Text(suggestion)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editSuggestion(suggestion)
                                } label: {
                                    Label("編輯", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    if let index = suggestions(for: selectedType).firstIndex(of: suggestion) {
                                        deleteSuggestion(for: selectedType, at: IndexSet(integer: index))
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
            .sheet(isPresented: $isEditing) {
                NavigationView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("編輯\(selectedType.rawValue)")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                        
                        HStack {
                            Text("目前Byte數: ")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.blue)
                            
                            // 檢查編輯文本的錯誤和Byte數
                            if editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("0 byte")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                            } else if let error = editingByteStatus.isEmpty ? nil : editingByteStatus {
                                Text(error)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.red)
                            } else if let bytes = parseHexInput(editingText) {
                                Text("\(bytes.count) byte")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                            } else {
                                Text("格式錯誤")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding()
                        
                        TextField("輸入\(selectedType.rawValue)", text: $editingText)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .autocapitalization(.allCharacters)
                            .focused($focusState)
                            .onChange(of: editingText) { newValue in
                                // 檢查長度限制
                                let maxLength: Int = 26
                                if let bytes = parseHexInput(newValue), bytes.count > maxLength {
                                    editingText = String(newValue.dropLast(2))
                                    triggerInputLimitFeedback()
                                }
                                
                                // 驗證格式和內容
                                validateEditingText(newValue){ correct in
                                    editingText = correct
                                }
                            }
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(editingByteStatus.isEmpty ? Color.secondary : Color.red, lineWidth: 2)
                            )

                        Spacer()
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                isEditing = false
                            }
                            .font(.system(size: 18, weight: .bold, design: .serif))
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("儲存") {
                                saveEditedSuggestion()
                                isEditing = false
                            }
                            .font(.system(size: 18, weight: .bold, design: .serif))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    func binding(for type: SuggestionType) -> Binding<String> {
        switch type {
        case .mask: return $maskInput
        case .data: return $dataInput
        }
    }

    func suggestions(for type: SuggestionType) -> [String] {
        switch type {
        case .mask: return maskSuggestions
        case .data: return dataSuggestions
        }
    }
    
    func errorBinding(for type: SuggestionType) -> Binding<String?> {
        switch type {
        case .mask: return $maskError
        case .data: return $dataError
        }
    }

    func addSuggestion(for type: SuggestionType) {
        let inputBinding = binding(for: type)
        let list = suggestions(for: type)
        let trimmed = inputBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !list.contains(trimmed) else { return }

        switch type {
        case .mask:
            maskSuggestions.append(trimmed)
            maskInput = ""
        case .data:
            dataSuggestions.append(trimmed)
            dataInput = ""
        }
    }

    func deleteSuggestion(for type: SuggestionType, at offsets: IndexSet) {
        switch type {
        case .mask: maskSuggestions.remove(atOffsets: offsets)
        case .data: dataSuggestions.remove(atOffsets: offsets)
        }
    }
    
    func editSuggestion(_ suggestion: String) {
        if let index = suggestions(for: selectedType).firstIndex(of: suggestion) {
            editingIndex = index
            editingText = suggestion
            
            // 立即驗證編輯文本
            validateEditingText(suggestion){ newValue in
                editingText = newValue
                
            }
            
            isEditing = true
        }
    }
    
    // 修改 saveEditedSuggestion 函數
    func saveEditedSuggestion() {
        guard let index = editingIndex else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        // 寫回資料
        switch selectedType {
        case .mask:
            maskSuggestions[index] = trimmed
        case .data:
            dataSuggestions[index] = trimmed
        }
    }

    
    private func parseHexInput(_ input: String) -> [UInt8]? {
        let cleaned = input.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined().uppercased()
        guard cleaned.count % 2 == 0 else { return nil }
            
        var result: [UInt8] = []
        var index = cleaned.startIndex
            
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            if nextIndex <= cleaned.endIndex {
                let hexStr = String(cleaned[index..<nextIndex])
                if let byte = UInt8(hexStr, radix: 16) {
                    result.append(byte)
                } else {
                    return nil
                }
            }
            index = nextIndex
        }
            
        return result.isEmpty ? nil : result
    }
    
    func isAsciiSafe(_ data: [UInt8]) -> Bool {
        for byte in data {
            if byte > 0x7F {
                return false
            }
        }
        return true
    }
    
    // 添加用於驗證編輯文本的函數
    func validateEditingText(_ text: String, setInput: @escaping (String) -> Void) {
        // 如果文本為空，清除錯誤狀態
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editingByteStatus = ""
            return
        }
        
        // 檢查十六進位格式
        guard let bytes = parseHexInput(text) else {
            editingByteStatus = "\(selectedType.rawValue)格式錯誤"
            return
        }
        
        // 檢查ASCII範圍
        if !isAsciiSafe(bytes) {
            editingByteStatus = "\(selectedType.rawValue)應在 01~7F 內"
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1102)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 保留格式，只刪掉最後兩個字元（避免跳動感太重）
                let trimmed = String(text.dropLast(2))
                setInput(trimmed)
            }
            return
        }
        
        // 檢查是否包含0x00
        if bytes.contains(0x00) {
            editingByteStatus = "\(selectedType.rawValue)不能包含 00"
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1102)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 保留格式，只刪掉最後兩個字元（避免跳動感太重）
                let trimmed = String(text.dropLast(2))
                setInput(trimmed)
            }
            return
        }
        
        // 如果沒有錯誤，清除錯誤狀態
        editingByteStatus = ""
    }
    
    // 修改后的 validateField 函数
    func validateField(
        originalInput: String,
        errorBinding: inout String?,
        fieldName: String,
        parseHex: (String) -> [UInt8]?,
        isAsciiSafe: ([UInt8]) -> Bool,
        setInput: @escaping (String) -> Void
    ) {
        // 如果输入为空，清除错误并返回
        if originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorBinding = nil
            return
        }
        
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
    
    // 修改后的 combinedError 计算属性
    var combinedError: String? {
        switch selectedType {
        case .mask:
            return maskError
        case .data:
            return dataError
        }
    }
    
    // 修改后的 enforceMaxLength 函数
    func enforceMaxLength(
        originalInput: String,
        input: inout String,
        parseHex: (String) -> [UInt8]?,
    ) {
        if originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        
        let cleanedHex = originalInput.cleanedHex
        guard let inputBytes = parseHex(cleanedHex) else {
            return
        }
        
        // 根據不同的 type 設定不同的最大長度
        let maxLength: Int
        switch selectedType {
        case .mask:
            maxLength = 26
        case .data:
            maxLength = 26
        }

        if inputBytes.count > maxLength {
            // 超過最大長度，刪掉原始輸入尾端兩個字元（不破壞空白或逗號格式）
            input = String(originalInput.dropLast(2))
            triggerInputLimitFeedback()
            AudioServicesPlaySystemSound(1103)
        } else {
            input = originalInput
        }
    }
    
    func triggerInputLimitFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}
