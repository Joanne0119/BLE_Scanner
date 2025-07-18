//
//  BLEScanerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/12.
//  最後更新 2025/07/08
//

import SwiftUI
import CoreBluetooth


enum BLEScannerField: Hashable {
    case mask
    case id
}

struct BLEScannerView: View {
    @StateObject private var scanner = CBLEScanner()
    @ObservedObject var packetStore: SavedPacketsStore
    @State private var maskText: String = ""
    @State private var idText: String = ""
    @State private var maskTextEmpty: Bool = false
    @State private var isExpanded: Bool = false
    @State private var rssiValue: Double = 200
    @State private var maskError: String?
    @FocusState private var focusedField: BLEScannerField?
    @Binding var maskSuggestions: [String]
    @State private var selectedDeviceID: String? = nil //用於儲存使用者點擊的裝置 ID，以便傳遞給 DetailView
    @State private var isLinkActive: Bool = false
    
    @State private var isTestInProgress = false
    
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
                backgroundTapGesture
                backgroundNavigationLink
                
                VStack(spacing: 20) {
                    inputSection
                    buttonSection
                    noMatchMessageView
                    deviceListView
                }
                .padding()
                .navigationTitle("掃描端")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        MQTTToolbarStatusView()
                    }
                }
            }
        }
        .navigationBarHidden(false)
        .navigationViewStyle(StackNavigationViewStyle())
    }
    private var backgroundNavigationLink: some View {
        NavigationLink(
            destination: detailViewDestination,
            isActive: $isLinkActive,
            label: { EmptyView() }
        )
    }
    @ViewBuilder
    private var detailViewDestination: some View {
        // 確保我們有選中的 deviceID 才建立 DetailView
        if let deviceID = selectedDeviceID {
            BLEScannerDetailView(
                packetStore: packetStore,
                scanner: scanner,
                deviceID: deviceID
            )
        } else {
            // 如果沒有 deviceID，為了安全提供一個空的 View
            EmptyView()
        }
    }
}

// MARK: - 背景點擊手勢
extension BLEScannerView {
    private var backgroundTapGesture: some View {
        Color.white.opacity(0.01)
            .onTapGesture {
                if focusedField != nil {
                    focusedField = nil
                }
            }
    }
}

// MARK: - 無匹配裝置訊息
extension BLEScannerView {
    private var noMatchMessageView: some View {
        Group {
            if scanner.noMatchFound {
                Text("找不到符合條件的裝置")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - 裝置列表
extension BLEScannerView {
    private var deviceListView: some View {
        List(filteredPackets) { packet in
            BLEPacketRowView(
                            packet: packet,
                            scanner: scanner,
                            packetStore: packetStore,
                            onSelect: { deviceID in
                                // 當一個 Row 被點擊時執行的程式碼
                                self.selectedDeviceID = deviceID
                                self.isLinkActive = true
                            }
                        )
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - 按鈕區塊
extension BLEScannerView {
    private var buttonSection: some View {
        VStack {
            if isTestInProgress {
                // 如果測試正在進行，顯示「完成測試」按鈕
                HStack {
                    Button("結束此測試", systemImage: "minus.circle.fill") {
                        isTestInProgress = false
                        if scanner.isScanning {
                            scanner.stopScanning()
                        }
                        TestSessionManager.shared.startNewTestSession()
                    }
                    .font(.system(size: 20, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    if let url = URL(string: "http://152.42.241.75:5000/api/chart") {
                        Link(destination: url) {
                            Label("查看圖表", systemImage: "chart.bar.xaxis")
                        }
                        .font(.system(size: 20, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding()
                
                HStack {
                    Button(scanner.isScanning ? "停止掃描" : "開始掃描") {
                        if scanner.isScanning {
                            scanner.stopScanning()
                        } else {
                            startScanningIfValid()
                        }
                    }
                    .font(.system(size: 20, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(scanner.isScanning ? .red : .blue)
                    
                    Button("常用遮罩掃描") {
                        maskText = "FFFFFFFFFFFFFFFFFFFFFFFFFF"
                        handleStartScan()
                    }
                    .font(.system(size: 20, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(scanner.isScanning)
                    
                    Button("", systemImage: "trash") {
                        scanner.matchedPackets.removeAll()
                    }
                    .tint(.red)
                }
                
            } else {
                // 如果沒有測試在進行，顯示「新測試」按鈕
                HStack {
                    Button("新測試", systemImage: "plus.circle.fill") {
                        isTestInProgress = true
                        TestSessionManager.shared.startNewTestSession()
                        scanner.matchedPackets.removeAll()
                    }
                    .font(.system(size: 20, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    if let url = URL(string: "http://152.42.241.75:5000/api/chart") {
                        Link(destination: url) {
                            Label("查看圖表", systemImage: "chart.bar.xaxis")
                        }
                        .font(.system(size: 20, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding()
            }
        }
    }
    
    private func startScanningIfValid() {
        let isMaskEmpty = maskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        maskTextEmpty = isMaskEmpty
        
        if isMaskEmpty {
            maskError = "請輸入遮罩"
            return
        }
        handleStartScan()
    }
}

// MARK: - 輸入區塊
extension BLEScannerView {
    private var inputSection: some View {
        VStack(alignment: .leading) {
            InputHeaderView(
                maskError: maskError,
                maskText: maskText,
                parseHexInput: parseHexInput
            )
            
            maskInputField
            
            if focusedField == .mask {
                MaskSuggestionsView(
                    maskSuggestions: maskSuggestions,
                    maskText: $maskText
                )
            }
        }
    }
    
    private var maskInputField: some View {
        HStack {
            Text("遮罩： ")
                .font(.system(size: 18, weight: .bold))
            
            ZStack {
                HStack {
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
                        .stroke(maskError == nil ? Color.secondary : Color.red, lineWidth: 2)
                )
            }
        }
    }
}

// MARK: - 輸入區標題視圖
struct InputHeaderView: View {
    let maskError: String?
    let maskText: String
    let parseHexInput: (String) -> [UInt8]?
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                currentByteCount
                Spacer()
                helpButton
            }
        }
    }
    
    private var currentByteCount: some View {
        HStack {
            Text("目前Byte數: ")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.blue)
            
            if let error = maskError {
                Text(error)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.red)
            } else {
                byteCountText
            }
        }
    }
    
    private var byteCountText: some View {
        Group {
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
    
    private var helpButton: some View {
        HelpButtonView {
            VStack {
                Text("掃描端篩選用的遮罩請輸入 00 ~ FF 十六進位的數字\n每一數字可用空白或逗點隔開（ex: 1A 2B, 3C）\n也可以不隔開（ex: 1A2B3C)\n")
                    .font(.system(size: 20, weight: .medium))
                Text("輸入遮罩後可按下「開始掃描」按鈕，即可獲得符合條件的裝置列表，列表中的內容為裝置ID與該裝置的rssi，點擊該裝置即可鎖定裝置，並進入裝置的詳細資料內容。\n詳細內容內可查看一定數據中最短的接收封包的時間、溫度、大氣壓力，以及該裝置鄰近裝置的ID與建議佈件移動方位。")
                    .font(.system(size: 20, weight: .medium))
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - 遮罩建議視圖
struct MaskSuggestionsView: View {
    let maskSuggestions: [String]
    @Binding var maskText: String
    
    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if maskSuggestions.filter({ !$0.isEmpty }).isEmpty {
                        Text("沒有自訂遮罩！")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(maskSuggestions, id: \.self) { suggestion in
                            suggestionButton(suggestion)
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: 60)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
    
    private func suggestionButton(_ suggestion: String) -> some View {
        Button(action: {
            maskText = suggestion
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

// MARK: - 輔助函數
extension BLEScannerView {
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
            errorBinding.wrappedValue = nil
        }
    }
}
