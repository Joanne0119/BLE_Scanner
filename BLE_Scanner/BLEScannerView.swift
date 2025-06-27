//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/06/20
//

import SwiftUI
import CoreBluetooth

struct BLEScannerView: View {
    enum Field: Hashable {
        case mask
        case id
    }
    
    @StateObject private var scanner = CBLEScanner()
    @ObservedObject var packetStore: SavedPacketsStore
    @State private var maskText: String = ""
    @State private var idText: String = ""
    @State private var maskTextEmpty = false
    @State private var idTextEmpty = false
    @State private var isExpanded: Bool = false
    @State private var rssiValue: Double = 100
    @State private var maskError: String?
    @FocusState private var focusedField: Field?
    @Binding var maskSuggestions: [String]
    
    var filteredPackets: [BLEPacket] {
        scanner.matchedPackets.values.filter { packet in
            
            let rssiMatch = packet.rssi >= -Int(rssiValue)
            return rssiMatch
        }
        .sorted(by: { $0.rssi > $1.rssi })
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.opacity(0.01)
                    .onTapGesture {
                        if focusedField != nil{
                            focusedField = nil
                        }
                    }
                VStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        DisclosureGroup(
                            isExpanded: $isExpanded,
                            content: {
                                HStack{
                                    VStack(alignment: .leading) {
                                        Text("請輸入 00 ~ FF 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                                            .font(.system(size: 15, weight: .light))
                                            .padding()
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(20)
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
                        VStack(alignment: .leading) {
                            HStack {
                                Text("目前Byte數: ")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                                
                                if let error = maskError {
                                    Text(error)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.red)
                                } else {
                                    let currentInput = maskText
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
                            .padding(.vertical)
                        }
                            
                        HStack {
                            Text("遮罩： ")
                                .font(.system(size: 18, weight: .bold))
                            ZStack(){
                                HStack(){
                                    TextField("ex：01 02 03", text: $maskText)
                                        .font(.system(size: 18, weight: .bold))
                                        .onChange(of: maskText) { newValue in
                                            scanner.expectedMaskText = newValue
                                            validateField(originalInput: newValue, errorBinding: $maskError)
                                        }
                                        .id("MaskScanner")
                                        .focused($focusedField, equals: .mask)
                                        .padding()
                                        
                                    if !maskText.isEmpty {
                                        Button(action: {
                                            maskText = ""
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
                                        .stroke(maskError == nil && maskTextEmpty == false ? Color.secondary : Color.red, lineWidth: 2)
                                )
//
                            }
                        }
                        if focusedField == .mask {
                            VStack {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        if maskSuggestions.filter({ !$0.isEmpty }).isEmpty {
                                            Text("沒有自訂遮罩！")
                                                .foregroundColor(.gray)
                                        } else{
                                            ForEach(maskSuggestions, id: \.self) { suggestion in
                                                Button(action: {
                                                    maskText = suggestion
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
                                .frame(height: 40)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    
                    
                    HStack {
                        Button(scanner.isScanning ? "停止掃描" : "開始掃描") {
                            if scanner.isScanning {
                                scanner.stopScanning()
                            } else {
                                let isMaskEmpty = maskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                
                                maskTextEmpty = isMaskEmpty
                                
                                if isMaskEmpty {
                                    
                                    return
                                }
                                handleStartScan()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(scanner.isScanning ? .red : .blue)
                        
                        Button("儲存掃描結果") {
                            scanner.stopScanning()
                            packetStore.append(filteredPackets)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brown)
                        
                    }
                    
                    if scanner.noMatchFound {
                        Text("找不到符合條件的裝置")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.red)
                    }
                    
                    
                    List(filteredPackets) { packet in
                        BLEPacketRowView(packet: packet)
                    }
                    .listStyle(PlainListStyle())
                    .navigationTitle("掃描端")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            MQTTToolbarStatusView()
                        }
                    }
                
                }
                .padding()

            }
        }
        .navigationBarHidden(false)
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
    
    func handleStartScan() {
        scanner.shouldStopScan = true
        scanner.expectedMaskText = maskText
        scanner.expectedIDText = idText
        scanner.startScanning()
    }
    
    private func hideKeyboard() {
       UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
   }
    
    private func validateField(originalInput: String, errorBinding: Binding<String?>) {
        if originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorBinding.wrappedValue = nil
            return
        }
        
        if parseHexInput(originalInput) == nil {
            errorBinding.wrappedValue = "遮罩格式錯誤"
        } else {
            // 格式正確，清除錯誤訊息
            errorBinding.wrappedValue = nil
        }
    }

}
