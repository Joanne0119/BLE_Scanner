//  最後更新 2025/07/17

import SwiftUI
import Foundation

struct PressureCorrectionView: View {
    enum Field: Hashable {
        case mask
        case base
        case basePressure
    }
    @StateObject private var scanner = CBLEScanner()
    @ObservedObject var offsetManager: PressureOffsetManager
    @Binding var maskSuggestions: [String]
    @State private var maskTextEmpty = false
    @State private var baseText: String = ""
    @State private var basePressureText: String = ""
    @State private var maskText: String = ""
    @FocusState private var focusedField: Field?
    @State private var isOn = false
    @State private var isCalibrationMode = false
    @State private var showingCalibrationAlert = false
    @State private var calibrationMessage = ""
    
    @State private var showingMQTTAlert = false
    @State private var mqttAlertMessage = ""
    @State private var isLoadingMQTTData = false
    
    // MQTT Debug
    @StateObject private var mqttdebugManager = MQTTManager()
    @State private var showDebugView = false


    var blePackets: [BLEPacket] {
        Array(scanner.matchedPackets.values)
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color.white.opacity(0.01)
                    .onTapGesture {
                        if focusedField != nil{
                            focusedField = nil
                        }
                    }
                VStack(spacing: 20) {
                    
                    toggleSection
                    
                    inputSection
                    
                    buttonSection
                    
                    Text("已掃描到 \(blePackets.count) 個")
                        .font(.system(size: 18, weight: .bold))
                    
                    dataTableView
                }
                .navigationTitle("大氣壓力校正")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        MQTTToolbarStatusView()
                    }
                }
                .padding()
                
                if isLoadingMQTTData {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("同步 MQTT 資料中...")
                            .font(.system(size: 16, weight: .medium))
                            .padding(.top, 10)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                }
                
            }
            .alert("校準結果", isPresented: $showingCalibrationAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(calibrationMessage)
            }
            .alert("MQTT 通知", isPresented: $showingMQTTAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(mqttAlertMessage)
            }
            .sheet(isPresented: $showDebugView) {
                MQTTDebugView(mqttManager: mqttdebugManager)
            }
        }
        .navigationBarHidden(false)
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - View Components
    
    private var toggleSection: some View {
        HStack(spacing: 10) {
           Toggle(isOn: $isCalibrationMode) {
               Text("校正模式")
           }
           .toggleStyle(iOSCheckboxToggleStyle())
           .foregroundStyle(isCalibrationMode ? .orange : .primary)
           .font(.system(size: 18, weight: .light))
           
       }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            maskInputSection
            
            if focusedField == .mask {
                maskSuggestionsView
            }
            
            if isCalibrationMode {
                baseAltitudeInputSection
            }
        }
    }
    
    private var maskInputSection: some View {
        HStack(alignment: .center) {
            Text("遮罩：")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 100, alignment: .leading)
            
            ZStack() {
                HStack {
                    TextField("ex：01 02 03", text: $maskText)
                        .font(.system(size: 18, weight: .bold))
                        .onChange(of: maskText) { _ in
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
        .padding(.horizontal)
    }
    
    private var maskSuggestionsView: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if maskSuggestions.filter({ !$0.isEmpty }).isEmpty {
                        Text("沒有自訂遮罩！")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(maskSuggestions, id: \.self) { suggestion in
                            Button(action: {
                                maskText = suggestion
                                focusedField = nil
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
    
    private var baseAltitudeInputSection: some View {
        VStack(){
            HStack(alignment: .center) {
                Text("海平面氣壓：")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 100, alignment: .leading)
                
                TextField("ex：1013.25（hPa）", text: $basePressureText)
                    .font(.system(size: 18, weight: .bold))
                    .keyboardType(.decimalPad)
                    .id("baseText")
                    .focused($focusedField, equals: .basePressure)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
            }
            .padding(.horizontal)
            HStack(alignment: .center) {
                Text("基準海拔：")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 100, alignment: .leading)
                
                TextField("ex：20（m）", text: $baseText)
                    .font(.system(size: 18, weight: .bold))
                    .keyboardType(.decimalPad)
                    .id("baseText")
                    .focused($focusedField, equals: .base)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
            }
            .padding(.horizontal)
        }
    }
    
    private var buttonSection: some View {
        HStack {
            Button(scanner.isScanning ? "停止掃描" : "開始掃描") {
                if scanner.isScanning {
                    scanner.stopScanning()
                } else {
                    let isMaskEmpty = maskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    maskTextEmpty = isMaskEmpty
                    
                    if isMaskEmpty { return }
                    
                    scanner.shouldStopScan = false
                    scanner.startScanning()
                }
            }
            .font(.system(size: 20, weight: .medium))
            .buttonStyle(.borderedProminent)
            .tint(scanner.isScanning ? .red : .blue)
            
            if isCalibrationMode {
                Button("執行校正") {
                    performCalibration()
                }
                .font(.system(size: 20, weight: .medium))
                .buttonStyle(.borderedProminent)
                .disabled(blePackets.isEmpty || baseText.isEmpty || basePressureText.isEmpty)
                .tint(.orange)
            }
        }
        .padding(.bottom)
    }
    
    private var dataTableView: some View {
        let columns = [
            GridItem(.fixed(30), spacing: 0),     // ID 欄位
            GridItem(.flexible(), spacing: 0),    // 原始大氣壓力欄位
            GridItem(.fixed(70), spacing: 0),      // offset
            GridItem(.flexible(),  spacing: 0)      // 校正後的大氣壓力
        ]
        
        return LazyVGrid(columns: columns, spacing: 0) {
            // 表格標題行
            tableHeaderView
            
            // 表格內容行
            ForEach(blePackets) { packet in
                TableRowView(
                    packet: packet,
                    offsetManager: offsetManager,
                )
            }
        }
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var tableHeaderView: some View {
        Group {
            Text("ID")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text("原始大氣壓力")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text("Offset")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                
            Text("校正大氣壓力")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.2))
    }
    // MARK: - Helper Methods
    
    private func performCalibration() {
        guard let baseAltitude = Double(baseText), baseAltitude > 0 else {
            calibrationMessage = "請輸入有效的基準海拔值"
            showingCalibrationAlert = true
            return
        }
        
        guard let basePressure = Double(basePressureText), basePressure > 0 else {
            calibrationMessage = "請輸入有效的目前海平面氣壓"
            showingCalibrationAlert = true
            return
        }
        
        let expectedPressure = pressureFromAltitude(baseAltitude, basePressure)
        let currentPackets = blePackets.filter { $0.parsedData != nil }
        
        if currentPackets.isEmpty {
            calibrationMessage = "沒有有效的壓力數據可以校正"
            showingCalibrationAlert = true
            return
        }
        
        var calibratedCount = 0
        for packet in currentPackets {
            if let parsedData = packet.parsedData {
                let offset = expectedPressure - parsedData.atmosphericPressure
                offsetManager.setOffset(for: packet.deviceID, offset: offset, baseAltitude: baseAltitude)
                calibratedCount += 1
            }
        }
        
        calibrationMessage = "成功校準 \(calibratedCount) 個裝置\n目前海平面氣壓\n基準海拔：\(baseAltitude)m\n標準壓力：\(String(format: "%.2f", expectedPressure))hPa"
        showingCalibrationAlert = true
    }
    
    private func pressureFromAltitude(_ altitude: Double, _ basePressure: Double) -> Double {
        let pressure = basePressure * pow((1 - (altitude / 44330.0)), 5.255)
        return pressure
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct TableRowView: View {
    let packet: BLEPacket
    let offsetManager: PressureOffsetManager
    
    var body: some View {
        Group {
            // ID 欄位
            deviceIDCell
            
            // 大氣壓力欄位
            pressureCell
            
            // offset欄位
//            timeCell
            offsetCell
            
            // 校正大氣壓力欄位
//            calibrationStatusCell
            calibrationPressureCell
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var deviceIDCell: some View {
        Text(packet.deviceID)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var pressureCell: some View {
        Group {
            if let parsedData = packet.parsedData {
                let deviceOffset = offsetManager.getOffset(for: packet.deviceID)
                let correctedPressure = parsedData.atmosphericPressure
                
                VStack(alignment: .center, spacing: 2) {
                    Text(String(format: "%.2f", correctedPressure))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    private var offsetCell: some View {
        Group{
            if offsetManager.isCalibrated(deviceId: packet.deviceID) {
                let deviceOffset = offsetManager.getOffset(for: packet.deviceID)
                Text(String(format: "%.2f", deviceOffset))
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            else {
                Text("--")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    private var calibrationPressureCell: some View {
        
        Group() {
            if let parsedData = packet.parsedData {
                let deviceOffset = offsetManager.getOffset(for: packet.deviceID)
                let correctedPressure = parsedData.atmosphericPressure + deviceOffset
                if offsetManager.isCalibrated(deviceId: packet.deviceID) {
                    Text(String(format: "%.2f", correctedPressure))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                else {
                    Text("--")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
  
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct iOSCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Button(action: {
                configuration.isOn.toggle()
            }, label: {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                configuration.label
            })
            
        }
        .opacity(1.0)
    }
}
