// 最後更新 2025/05/10

import SwiftUI

struct SettingView: View {
    enum SuggestionType: String, CaseIterable {
        case mask = "遮罩"
        case data = "內容"
    }

    @State private var selectedType: SuggestionType = .mask
    @State private var isExpanded: Bool = false

    @State private var maskInput = ""
    @State private var dataInput = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    @Binding var maskSuggestions: [String]
    @Binding var dataSuggestions: [String]

    var body: some View {
        VStack {
            Text("自訂輸入").font(.largeTitle).bold()

            Picker("選擇類型", selection: $selectedType) {
                ForEach(SuggestionType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    HStack{
                        VStack(alignment: .leading) {
                            Text("自訂遮罩與內容的快速選取欄位，此自訂內容會出現在廣播與掃描端的輸入框下方")
                                .font(.system(size: 12, weight: .light, design: .serif))
                            Text("請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                                .font(.system(size: 12, weight: .light, design: .serif))
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(20)
                            Text("* 不要使用 00，可能會導致00後的資料遺失")
                                .font(.system(size: 12, weight: .light, design: .serif))
                                .foregroundStyle(.red)
                        }
                        .padding()
                        
                        Spacer()
                    }
                }, label: {
                    Text("說明")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.black)
                }
            )
            .padding()

            
            

            VStack(alignment: .leading) {
                HStack {
                    Text("目前Byte數: ")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.blue)
                    let currentInput = binding(for: selectedType).wrappedValue
                    let cleanedInput = currentInput.components(separatedBy: CharacterSet(charactersIn: " ,，")).joined()

                    if cleanedInput.count % 2 != 0 {
                        Text("輸入不完整")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                    } else {
                        let bytes = parseHexInput(currentInput) ?? []
                        Text("\(bytes.count) byte")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                
                
                Text("自訂\(selectedType.rawValue)")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal)

                HStack {
                    TextField("輸入自訂\(selectedType.rawValue)", text: binding(for: selectedType))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                    Button("新增") {
                        addSuggestion(for: selectedType)
                    }
                    .alert(alertMessage, isPresented: $showAlert) {
                        Button("知道了", role: .cancel) { }
                    }
                }
                .padding(.horizontal)
            }

            List {
                ForEach(suggestions(for: selectedType), id: \.self) { suggestion in
                    Text(suggestion)
                }
                .onDelete { indices in
                    deleteSuggestion(for: selectedType, at: indices)
                }
            }
        }
        .padding()
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

    func addSuggestion(for type: SuggestionType) {
        let inputBinding = binding(for: type)
        let list = suggestions(for: type)
        let trimmed = inputBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !list.contains(trimmed) else { return }
        
        guard let bytes = parseHexInput(trimmed) else {
            alertMessage = "格式錯誤，請確保是有效的十六進位"
            showAlert = true
            return
        }
        
        if(!isAsciiSafe(bytes)){
            alertMessage = "格式錯誤，請確保是介於00至7F之間的有效十六進位"
            showAlert = true
            return
        }
        
        if(bytes.contains(0x00) ){
            alertMessage = "遮罩裡有 0x00，有可能會導致部分封包遺失！"
            showAlert = true
            return
        }

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
            if byte > 0x7A {
                return false
            }
        }
        return true
    }
}
