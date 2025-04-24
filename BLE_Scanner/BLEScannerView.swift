//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//

import SwiftUI
import CoreBluetooth

struct BLEScannerView: View {
    @StateObject private var scanner = CBLEScanner()
    
    @State private var maskText: String = ""
    @State private var idText: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

        var filteredPackets: [BLEPacket] {
            scanner.allPackets.values.filter { packet in
                let raw = packet.rawData.uppercased().replacingOccurrences(of: " ", with: "")
                
                // 檢查 Mask 篩選（從開頭）
                let maskMatch: Bool = {
                    guard !maskText.isEmpty else { return true }
                    let prefix = String(raw.prefix(maskText.count))
                    return prefix == maskText.uppercased()
                }()
                
                // 檢查 ID 篩選（從尾巴）
                let idMatch: Bool = {
                    guard !idText.isEmpty else { return true }
                    let tailByteStart = raw.count - 2
                    guard tailByteStart >= 0 else { return false }
                    let idByte = raw.suffix(2)
                    return idByte == idText.uppercased()
                }()
                
                return maskMatch && idMatch
            }
            .sorted(by: { $0.deviceName < $1.deviceName })
        }

        var body: some View {
            VStack(spacing: 20) {
                Text("掃描端").font(.largeTitle).bold()
                VStack(alignment: .leading) {
                    Text("篩選封包")
                    HStack {
                        Text("Mask: ")
                        TextField("Mask（例：A1B2C3）", text: $maskText)
                           .textFieldStyle(RoundedBorderTextFieldStyle())
                           .onChange(of: maskText) { scanner.expectedMaskText = maskText }
                           .id("MaskScanner")
                    }
                    HStack {
                        Text("ID: ")
                        TextField("ID（例：AA）", text: $idText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                            .onChange(of: idText) { scanner.expectedIDText = idText }
                            .id("IdScanner")
                    }
                   
               }
               .padding(.horizontal)
                HStack {
                    Button("開始掃描") {
                        if !maskText.isEmpty {
                            guard let _ = parseHexInput(maskText) else {
                                alertMessage = "遮罩格式錯誤，請確保是有效的十六進位"
                                showAlert = true
                                return
                            }
                        }
                        
                        // 解析ID (一個位元組)
                    if !idText.isEmpty {
                       guard let _ = UInt8(idText, radix: 16) else {
                           alertMessage = "ID 格式錯誤，請確保是有效的十六進位"
                           showAlert = true
                           return
                       }
                   }
    
                        scanner.expectedMaskText = maskText
                        scanner.expectedIDText = idText
                        scanner.startScanning()
                        
                    }
                    .buttonStyle(.borderedProminent)
                    .alert(alertMessage, isPresented: $showAlert) {
                        Button("知道了", role: .cancel) { }
                    }
                    
                    Button("停止掃描") {
                        scanner.stopScanning()
                    }
                    .buttonStyle(.borderedProminent)
                }

//                List(scanner.allPackets.values.sorted(by: { $0.deviceName < $1.deviceName })) { packet in
//                    VStack(alignment: .leading, spacing: 4) {
//                        Text("Name：\(packet.deviceName)")
//                        Text("RSSI：\(packet.rssi)")
//                        Text("Data：\(packet.rawData)")
//                    }
//                    .padding(6)
//                    .background(packet.isMatched ? Color.green.opacity(0.3) : Color.clear)
//                    .foregroundColor(packet.isMatched ? .green : .primary)
//                    .cornerRadius(8)
//                }
                if scanner.noMatchFound {
                    Text("找不到符合條件的裝置")
                        .foregroundColor(.red)
                }

                List(filteredPackets) { packet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name：\(packet.deviceName)")
                        Text("RSSI：\(packet.rssi)")
                        Text("Data：\(packet.rawData)")
                    }
                    .padding(6)
                    .background(packet.isMatched ? Color.green.opacity(0.3) : Color.clear)
                    .foregroundColor(packet.isMatched ? .green : .primary)
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    
    private func parseHexInput(_ input: String) -> [UInt8]? {
            let cleaned = input.replacingOccurrences(of: " ", with: "").uppercased()
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
}
#Preview {
    BLEScannerView()
}
