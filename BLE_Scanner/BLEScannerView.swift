//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/06/14
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
                                    ZStack(){
                                        HStack(){
                                            TextField("ex：01 02 03", text: $maskText)
                                                .font(.system(size: 18, weight: .bold, design: .serif))
                                                .onChange(of: maskText) {_ in
                                                    scanner.expectedMaskText = maskText
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
                                                .stroke(maskTextEmpty == false ? Color.secondary : Color.red, lineWidth: 2)
                                        )
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
                                HStack {
                                    Text("ID： ")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    ZStack(){
                                        HStack(){
                                            TextField("ex：01", text: $idText)
                                                .font(.system(size: 18, weight: .bold, design: .serif))
                                                .onChange(of: idText) { _ in
                                                    scanner.expectedIDText = idText
                                                }
                                                .id("IdScanner")
                                                .focused($focusedField, equals: .id)
                                                .padding()
                                            if !idText.isEmpty {
                                                Button(action: {
                                                    idText = ""
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
                                                .stroke(idTextEmpty == false ? Color.secondary : Color.red, lineWidth: 2)
                                        )
                                    }
                                    
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
                        Button(scanner.isScanning ? "停止掃描" : "開始掃描") {
                            if scanner.isScanning {
                                scanner.stopScanning()
                            } else {
                                let isMaskEmpty = maskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                // 設定錯誤狀態
                                maskTextEmpty = isMaskEmpty
                                
                                if isMaskEmpty {
                                    withAnimation {
                                        isExpanded = true // 展開區塊
                                    }
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
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(.red)
                    }
                    
                    List(filteredPackets) { packet in
                        VStack(alignment: .leading, spacing: 4) {
                            if let parsedData = packet.parsedData {
                               
                               VStack(alignment: .leading, spacing: 4) {
                                   Text("ID：\(packet.deviceID)")
                                       .font(.system(size: 16, weight: .regular, design: .serif))
                                   Text("RSSI：\(packet.rssi) dBm")
                                       .font(.system(size: 16, weight: .regular, design: .serif))
                                   HStack {
                                       Text("⏱️ 時間：\(parsedData.seconds) 秒")
                                           .font(.system(size: 15, weight: .medium, design: .serif))
                                       Spacer()
                                       if parsedData.hasReachedTarget {
                                           Text("已達標")
                                               .font(.system(size: 14, weight: .bold, design: .serif))
                                               .foregroundColor(.green)
                                               .padding(.horizontal, 8)
                                               .padding(.vertical, 2)
                                               .background(Color.green.opacity(0.2))
                                               .cornerRadius(4)
                                       }
                                   }
                                   
                                   Text("🌡️ 大氣壓力：\(String(format: "%.2f", parsedData.atmosphericPressure)) hPa")
                                       .font(.system(size: 15, weight: .medium, design: .serif))
                                   
                                   Text("📱 裝置接收狀況：")
                                       .font(.system(size: 15, weight: .medium, design: .serif))
                                       .padding(.top, 4)
                                   
                                   VStack(alignment: .leading, spacing: 2) {
                                       ForEach(Array(parsedData.devices.enumerated()), id: \.offset) { index, device in
                                           HStack {
                                               
                                               Text("ID: \(String(format: "%02X", device.deviceId))")
                                                   .font(.system(size: 14, weight: .regular, design: .serif))
                                                   .frame(width: 50, alignment: .leading)
                                               
                                               Text("次數: \(device.count)")
                                                   .font(.system(size: 14, weight: .regular, design: .serif))
                                                   .frame(width: 60, alignment: .leading)
                                               
                                               Spacer()
                                               
                                               Text("\(String(format: "%.1f", device.receptionRate)) 次/秒")
                                                   .font(.system(size: 14, weight: .bold, design: .serif))
                                                   .foregroundColor(device.count >= 100 ? .green : .primary)
                                           }
                                       }
                                   }
                                   .padding(.leading, 8)
                               }
                               .padding(.top, 8)
                           }
                            
                        }
                        .padding()
                        .cornerRadius(8)
                    }
                    .cornerRadius(8)
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

}

