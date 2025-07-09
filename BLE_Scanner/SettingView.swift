//  最後更新 2025/07/08

import SwiftUI
import AVFoundation
import UIKit

struct SettingView: View {
    @EnvironmentObject var mqttManager: MQTTManager
    
    enum SuggestionType: String, CaseIterable {
        case mask = "遮罩"
        case data = "內容"
        
        var topicKey: String {
            switch self {
            case .mask: return "mask"
            case .data: return "data"
            }
        }
    }

    @State private var selectedType: SuggestionType = .mask
    @State private var isExpanded: Bool = false
    @FocusState private var focusState: Bool

    @State private var maskInput = ""
    @State private var dataInput = ""

    @State private var maskError: String?
    @State private var dataError: String?
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var editingIndex: Int? = nil
    @State private var editingByteStatus: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.opacity(0.01)
                    .onTapGesture {
                        if focusState != false{
                            focusState = false
                        }
                    }
                VStack {
                    
                    // MARK: - 客製化的 Segmented Picker
                    CustomSegmentedControl(selectedType: $selectedType)
                        .offset(y: 20)
                        .onChange(of: selectedType) { newType in
                            // 重新驗證當前選定類型的輸入內容
                            let currentInput = binding(for: newType).wrappedValue
                            validateField(
                                originalInput: currentInput,
                                errorBinding: &errorBinding(for: newType).wrappedValue,
                                fieldName: newType.rawValue,
                                parseHex: parseHexInput
                            ) { corrected in
                                binding(for: newType).wrappedValue = corrected
                            }
                        }
                    
//                    VStack {
                        VStack(alignment: .leading) {
                            HStack {
                                HStack {
                                    Text("目前Byte數: ")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.blue)
                                    
                                    if let error = combinedError {
                                        Text(error)
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(.red)
                                    } else {
                                        let currentInput = binding(for: selectedType).wrappedValue
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
                                
                                Spacer()
                                HelpButtonView {
                                    VStack(alignment: .leading) {
                                        Text("此為自訂遮罩與自訂內容的快速選取欄位，此自訂內容會出現在廣播與掃描端的輸入框下方\n")
                                            .font(.system(size: 25, weight: .medium))
                                        
                                        Text("請輸入 00 ~ FF 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）\n")
                                            .font(.system(size: 20, weight: .medium))
                                        Text("注意：\n廣播端只能使用 01 ~ 7F 十六進位的數字。\n掃描端為00 ~ FF 十六進位的數字")
                                            .foregroundColor(.red)
                                            .font(.system(size: 20, weight: .medium))
                                    }
                                    .padding()
                                }
                                .padding()
                            }
                            
                            Text("自訂\(selectedType.rawValue)")
                                .font(.system(size: 18, weight: .bold))
                                .padding(.horizontal)
                            
                            HStack {
                                HStack {
                                    TextField("輸入自訂\(selectedType.rawValue)", text: binding(for: selectedType))
                                        .font(.system(size: 18, weight: .bold))
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
                                                parseHex: parseHexInput) { corrected in
                                                    binding(for: selectedType).wrappedValue = corrected
                                                }
                                        }
                                    
                                    if !binding(for: selectedType).wrappedValue.isEmpty {
                                        Button(action: {
                                            binding(for: selectedType).wrappedValue = ""
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .transition(.opacity)
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
                                .font(.system(size: 18, weight: .bold))
                            }
                            .padding(.horizontal)
                            .animation(.easeInOut(duration: 0.2), value: binding(for: selectedType).wrappedValue.isEmpty)
                        
                        // 背景區域
                        List {
                            ForEach(suggestions(for: selectedType), id: \.self) { suggestion in
                                HStack {
                                    // 文字內容
                                    Text(suggestion)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color("bgGray"))
                                )
                                .onTapGesture {
                                    binding(for: selectedType).wrappedValue = suggestion
                                }
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
                        .listStyle(PlainListStyle())
                        .padding()
                        
                    }
                    .padding()
                    .background(.white)
                }
                .background(Color("bgGray"))
                .navigationTitle("自訂輸入")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        MQTTToolbarStatusView()
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("編輯\(selectedType.rawValue)")
                                .font(.system(size: 20, weight: .bold))
                            
                            HStack {
                                Text("目前Byte數: ")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                                
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
                                .font(.system(size: 18, weight: .bold))
                                .autocapitalization(.allCharacters)
                                .focused($focusState)
                                .onChange(of: editingText) { newValue in
                                    let maxLength: Int = 26
                                    if let bytes = parseHexInput(newValue), bytes.count > maxLength {
                                        editingText = String(newValue.dropLast(2))
                                        triggerInputLimitFeedback()
                                    }
                                    
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
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("儲存") {
                                    saveEditedSuggestion()
                                    isEditing = false
                                }
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(false)
        .navigationViewStyle(StackNavigationViewStyle())
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
        case .mask: return mqttManager.maskSuggestions
        case .data: return mqttManager.dataSuggestions
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
        
        mqttManager.publishSuggestion(suggestion: trimmed, typeKey: type.topicKey, action: "add")

        switch type {
        case .mask:
            mqttManager.maskSuggestions.append(trimmed)
            maskInput = ""
        case .data:
            mqttManager.dataSuggestions.append(trimmed)
            dataInput = ""
        }
    }

    func deleteSuggestion(for type: SuggestionType, at offsets: IndexSet) {
        let suggestionsToDelete = offsets.map { suggestions(for: type)[$0] }
        for suggestion in suggestionsToDelete {
            mqttManager.publishSuggestion(suggestion: suggestion, typeKey: type.topicKey, action: "delete")
        }
        
        switch type {
        case .mask: mqttManager.maskSuggestions.remove(atOffsets: offsets)
        case .data: mqttManager.dataSuggestions.remove(atOffsets: offsets)
        }
    }
    
    func editSuggestion(_ suggestion: String) {
        if let index = suggestions(for: selectedType).firstIndex(of: suggestion) {
            editingIndex = index
            editingText = suggestion
            
            validateEditingText(suggestion){ newValue in
                editingText = newValue
            }
            
            isEditing = true
        }
    }
    
    func saveEditedSuggestion() {
        guard let index = editingIndex else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }
        
        let originalSuggestion: String
        switch selectedType {
        case .mask: originalSuggestion = mqttManager.maskSuggestions[index]
        case .data: originalSuggestion = mqttManager.dataSuggestions[index]
        }
        
        if originalSuggestion != trimmed {
            mqttManager.publishSuggestion(suggestion: originalSuggestion, typeKey: selectedType.topicKey, action: "delete")
            mqttManager.publishSuggestion(suggestion: trimmed, typeKey: selectedType.topicKey, action: "add")
        }

        switch selectedType {
        case .mask:
            mqttManager.maskSuggestions[index] = trimmed
        case .data:
            mqttManager.dataSuggestions[index] = trimmed
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
    
    func validateEditingText(_ text: String, setInput: (String) -> Void) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editingByteStatus = ""
            return
        }
        
        guard parseHexInput(text) != nil else {
            editingByteStatus = "\(selectedType.rawValue)格式錯誤"
            return
        }
        
        editingByteStatus = ""
    }
    
    func validateField(
        originalInput: String,
        errorBinding: inout String?,
        fieldName: String,
        parseHex: (String) -> [UInt8]?,
        setInput: (String) -> Void
    ) {
        if originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorBinding = nil
            return
        }
        
        let cleanedHex = originalInput.cleanedHex
        guard parseHex(cleanedHex) != nil else {
            errorBinding = "\(fieldName)格式錯誤"
            return
        }
        
        errorBinding = nil
    }
    
    var combinedError: String? {
        switch selectedType {
        case .mask:
            return maskError
        case .data:
            return dataError
        }
    }
    
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
        
        let maxLength: Int
        switch selectedType {
        case .mask:
            maxLength = 26
        case .data:
            maxLength = 26
        }

        if inputBytes.count > maxLength {
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

// MARK: - 客製化 Segmented Control 元件
struct CustomSegmentedControl: View {
    @Binding var selectedType: SettingView.SuggestionType
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingView.SuggestionType.allCases, id: \.self) { type in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedType = type
                    }
                }) {
                    Text(type.rawValue)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(selectedType == type ? .blue : .gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                        .background(
                            ZStack {
                                if selectedType == type {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                        .matchedGeometryEffect(id: "segment", in: animation)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color("bgGray"))
        .cornerRadius(12)
    }
}
