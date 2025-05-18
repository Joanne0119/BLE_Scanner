//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/05/18
//

import SwiftUI
import CoreBluetooth

struct BLEScannerView: View {
    enum Field: Hashable {
        case mask
        case id
    }
    
    @StateObject private var scanner = CBLEScanner()
    @State private var maskText: String = ""
    @State private var idText: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isExpanded: Bool = false
    @State private var rssiValue: Double = 100
    @FocusState private var focusedField: Field?
    @Binding var maskSuggestions: [String]
    
        var filteredPackets: [BLEPacket] {
            scanner.matchedPackets.values.filter { packet in
                
                let rssiMatch = packet.rssi >= -Int(rssiValue)
                return rssiMatch
            }
            .sorted(by: { $0.deviceName < $1.deviceName })
        }

        var body: some View {
            ZStack {
                Color.white.opacity(0.01)
                    .onTapGesture {
                        if focusedField != nil{
                            focusedField = nil
                        }
                    }
                VStack(spacing: 20) {
                    Text("掃描端").font(.largeTitle).bold()
                    DisclosureGroup(
                        isExpanded: $isExpanded,
                        content: {
                            VStack(alignment: .leading) {
                                Text("請輸入 01 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C）")
                                    .font(.system(size: 15, weight: .light, design: .serif))
                                    .padding(.vertical)
                                HStack {
                                    Text("遮罩： ")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    TextField("ex：01 02 03", text: $maskText)
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                        .onChange(of: maskText) {
                                            _ in scanner.expectedMaskText = maskText }
                                        .id("MaskScanner")
                                        .focused($focusedField, equals: .mask)
                                        .padding()
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(Color.secondary, lineWidth: 2)
                                        )
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
                                HStack {
                                    Text("ID： ")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    TextField("ex：01", text: $idText)
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                        .onChange(of: idText) { _ in scanner.expectedIDText = idText }
                                        .id("IdScanner")
                                        .focused($focusedField, equals: .id)
                                        .padding()
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(Color.secondary, lineWidth: 2)
                                        )
                                }
                                HStack {
                                    Text("RSSI: ")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    Text("-\(round(rssiValue).formatted()) dBm")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    Slider(value: $rssiValue, in: 30...100)
                                        
                                        .onChange(of: rssiValue) { _ in scanner.expectedRSSI = rssiValue }
                                        .id("RSSIScanner")
                                }
                                
                            }
                            .padding()
                            
                        }, label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("篩選封包")
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                            }
                            .font(.system(size: 17, weight: .bold))
                        }
                                
                    )
                    .padding()
                    
                    HStack {
                        Button("開始掃描") {
                            handleStartScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .alert(alertMessage, isPresented: $showAlert) {
                            Button("知道了", role: .cancel) { }
                        }
                        .disabled(scanner.isScanning)
                        
                        Button("停止掃描") {
                            scanner.stopScanning()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!scanner.isScanning)
                    }
                    
                    if scanner.noMatchFound {
                        Text("找不到符合條件的裝置")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(.red)
                    }
                    
                    List(filteredPackets) { packet in
                        VStack(alignment: .leading, spacing: 4) {
                            //                        Text("Name：\(packet.deviceName)")
                            Text("ID：\(packet.deviceID)")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                            Text("RSSI：\(packet.rssi) dBm")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                            Text("Data：\(packet.rawData)")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                        }
                        .padding()
                        .cornerRadius(8)
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
    
    func handleStartScan() {
        var maskByte: [UInt8] = []
        var idByte: [UInt8] = []
        
        if !maskText.isEmpty {
            guard let parsedMask = parseHexInput(maskText) else {
                alertMessage = "遮罩格式錯誤，請確保是有效的十六進位"
                showAlert = true
                return
            }
            if (!isAsciiSafe(parsedMask)) {
                alertMessage = "遮罩格式錯誤，請確保是介於00至7F之間的有效十六進位"
                showAlert = true
                return
            }
            maskByte = parsedMask
        }
        
        if !idText.isEmpty {
            guard let parsedID = parseHexInput(idText) else {
                alertMessage = "ID 格式錯誤，請確保是有效的十六進位"
                showAlert = true
                return
            }
            if (!isAsciiSafe(parsedID)) {
                alertMessage = "ID 格式錯誤，請確保是介於00至7F之間的有效十六進位"
                showAlert = true
                return
            }
            idByte = parsedID
        }
        
        if !maskText.isEmpty && !maskSuggestions.contains(maskText) {
            maskSuggestions.append(maskText)
        }
        
        scanner.expectedMaskText = maskText
        scanner.expectedIDText = idText
        scanner.startScanning()
    }
    
    private func hideKeyboard() {
       UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
   }

}

