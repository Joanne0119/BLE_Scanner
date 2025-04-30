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
    @State private var isExpanded: Bool = false
    @State private var rssiValue: Double = 100

        var filteredPackets: [BLEPacket] {
            scanner.matchedPackets.values.filter { packet in
                _ = packet.rawData.uppercased().replacingOccurrences(of: " ", with: "")
                
                let rssiMatch = packet.rssi >= -Int(rssiValue)
                return rssiMatch
            }
            .sorted(by: { $0.deviceName < $1.deviceName })
        }

        var body: some View {
            VStack(spacing: 20) {
                Text("掃描端").font(.largeTitle).bold()
                DisclosureGroup("篩選封包", isExpanded: $isExpanded){
                    VStack(alignment: .leading) {
                        Text("請輸入 00 ~ 7F 十六進位的數字\n每一數字可用空白或逗點隔開（ex: AA BB, CC）\n也可以不隔開（ex: AABBCC）")
                            .font(.system(size: 12, weight: .light, design: .serif))
                            .padding(.vertical)
                        HStack {
                            Text("遮罩: ")
                            TextField("ex：01 02 03", text: $maskText)
                               .textFieldStyle(RoundedBorderTextFieldStyle())
                               .onChange(of: maskText) { scanner.expectedMaskText = maskText }
                               .id("MaskScanner")
                        }
                        HStack {
                            Text("ID: ")
                            TextField("ex：01", text: $idText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: idText) { scanner.expectedIDText = idText }
                                .id("IdScanner")
                        }
                        HStack {
                            Text("RSSI: ")
                            Text("-\(round(rssiValue).formatted()) dBm")
                            Slider(value: $rssiValue, in: 30...100)
                                .onChange(of: idText) { scanner.expectedRSSI = rssiValue }
                                .id("RSSIScanner")
                        }
                       
                   }
                   .padding()
                }
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
                        .foregroundColor(.red)
                }

                List(filteredPackets) { packet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name：\(packet.deviceName)")
                        Text("RSSI：\(packet.rssi)")
                        Text("Data：\(packet.rawData)")
                    }
                    .padding()
                    .cornerRadius(8)
                }
            }
            .padding()
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
        
        scanner.expectedMaskText = maskText
        scanner.expectedIDText = idText
        scanner.startScanning()
    }

}


#Preview {
    BLEScannerView()
}
