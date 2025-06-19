//  最後更新 2025/06/19

import SwiftUI
import Foundation

struct PressureCorrectionView: View {
    enum Field: Hashable {
        case mask
        case base
    }
    @StateObject private var scanner = CBLEScanner()
    @StateObject private var offsetManager = PressureOffsetManager()
    @Binding var maskSuggestions: [String]
    @State private var maskTextEmpty = false
    @State private var baseText: String = ""
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
        ZStack {
            Color.white.opacity(0.01)
                .onTapGesture {
                    if focusedField != nil{
                        focusedField = nil
                    }
                }
            VStack(spacing: 20) {
                Text("大氣壓力校正")
                    .font(.largeTitle).bold()
                HStack{
                    mqttStatusSection
                    mqttControlSection
                    Button("", systemImage: "ladybug") {
                        showDebugView = true
                    }
                    .tint(.gray)
                    .padding(.trailing)
                }
                .padding()
                
                toggleSection
                
                inputSection
                
                buttonSection
                
                Text("已掃描到 \(blePackets.count) 個")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                
                dataTableView
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
        .onAppear {
//            offsetManager.loadOffsets()
            loadOffsetsAndConnectMQTT()
            mqttdebugManager.connect()
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
    
    // MARK: - MQTT View Components
    private var mqttStatusSection: some View {
        HStack {
            Circle()
                .fill(offsetManager.mqttStatus == "已連接" ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            
            Text("MQTT: \(offsetManager.mqttStatus)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(offsetManager.mqttStatus == "已連接" ? .green : .red)
            
            Spacer()
            
            if isLoadingMQTTData {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal)
    }
    
    private var mqttControlSection: some View {
        HStack(spacing: 15) {
            Button("", systemImage: "arrow.trianglehead.2.clockwise") {
                syncFromServer()
            }
            .disabled(offsetManager.mqttStatus != "已連接")
            
            Button("", systemImage: "link") {
                reconnectMQTT()
            }
            .tint(.orange)
        }

    }
    
    // MARK: - View Components
    
    private var toggleSection: some View {
        HStack(spacing: 10) {
           Toggle(isOn: $isCalibrationMode) {
               Text("校正模式")
           }
           .toggleStyle(iOSCheckboxToggleStyle())
           .foregroundStyle(isCalibrationMode ? .orange : .primary)
           .font(.system(size: 18, weight: .light, design: .serif))
           
           Toggle(isOn: $isOn) {
               Text("套用偏差值")
           }
           .toggleStyle(iOSCheckboxToggleStyle())
           .foregroundStyle(isOn ? .green : .primary)
           .font(.system(size: 18, weight: .light, design: .serif))
           .disabled(isCalibrationMode)
           .opacity(isCalibrationMode ? 0.4 : 1.0)
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
                .font(.system(size: 18, weight: .bold, design: .serif))
                .frame(width: 100, alignment: .leading)
            
            ZStack {
                HStack {
                    TextField("ex：01 02 03", text: $maskText)
                        .font(.system(size: 18, weight: .bold, design: .serif))
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
        HStack(alignment: .center) {
            Text("基準海拔：")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .frame(width: 100, alignment: .leading)
            
            TextField("ex：20（m）", text: $baseText)
                .font(.system(size: 18, weight: .bold, design: .serif))
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
            .buttonStyle(.borderedProminent)
            .tint(scanner.isScanning ? .red : .blue)
            
            if isCalibrationMode {
                Button("執行校正") {
                    performCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(blePackets.isEmpty || baseText.isEmpty)
                .tint(.orange)
            }
        }
        .padding(.bottom)
    }
    
    private var dataTableView: some View {
        let columns = [
            GridItem(.fixed(50), spacing: 0),     // ID 欄位
            GridItem(.flexible(), spacing: 0),    // 大氣壓力欄位
            GridItem(.fixed(80), spacing: 0),      // 時間欄位
            GridItem(.fixed(60), spacing: 0)      // 校症狀態
        ]
        
        return LazyVGrid(columns: columns, spacing: 0) {
            // 表格標題行
            tableHeaderView
            
            // 表格內容行
            ForEach(blePackets) { packet in
                TableRowView(
                    packet: packet,
                    offsetManager: offsetManager,
                    isOn: isOn
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
            
            Text("大氣壓力 (hPa)")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text("時間")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                
            Text("校正")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.2))
    }
    
    //MARK: - MQTT Methods
    private func loadOffsetsAndConnectMQTT() {
        isLoadingMQTTData = true
        
        // 載入本地偏差值
        offsetManager.loadOffsets()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.offsetManager.connectMQTT()
        }
        
        // 監聽 MQTT 連接狀態變化
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.isLoadingMQTTData = false
            
            if self.offsetManager.mqttStatus == "已連接" {
                self.mqttAlertMessage = "MQTT 連接成功，已同步伺服器資料"
                self.showingMQTTAlert = true
            } else {
                self.mqttAlertMessage = "MQTT 連接失敗，僅使用本地資料"
                self.showingMQTTAlert = true
            }
        }
    }
    
    private func syncFromServer() {
        guard offsetManager.mqttStatus == "已連接" else {
            mqttAlertMessage = "MQTT 未連接，無法同步資料"
            showingMQTTAlert = true
            return
        }
        
        isLoadingMQTTData = true
        
        // 請求伺服器所有偏差值
        offsetManager.requestAllOffsetsFromServer()
        
        // 模擬同步過程
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isLoadingMQTTData = false
            self.mqttAlertMessage = "資料同步完成"
            self.showingMQTTAlert = true
        }
    }
    
    private func reconnectMQTT() {
        mqttAlertMessage = "正在重新連接 MQTT..."
        showingMQTTAlert = true
        
        offsetManager.disconnectMQTT()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.offsetManager.connectMQTT()
        }
    }
    
    // MARK: - Helper Methods
    
    private func performCalibration() {
        guard let baseAltitude = Double(baseText), baseAltitude > 0 else {
            calibrationMessage = "請輸入有效的基準海拔值"
            showingCalibrationAlert = true
            return
        }
        
        let expectedPressure = pressureFromAltitude(baseAltitude)
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
        
        calibrationMessage = "成功校準 \(calibratedCount) 個裝置\n基準海拔：\(baseAltitude)m\n標準壓力：\(String(format: "%.2f", expectedPressure))hPa"
        showingCalibrationAlert = true
    }
    
    private func pressureFromAltitude(_ altitude: Double) -> Double {
        let pressure = 1013.25 * pow((1 - (altitude / 44330.0)), 5.255)
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
    let isOn: Bool
    
    var body: some View {
        Group {
            // ID 欄位
            deviceIDCell
            
            // 大氣壓力欄位
            pressureCell
            
            // 時間欄位
            timeCell
            
            // 校正狀態欄位
            calibrationStatusCell
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
                let correctedPressure = isOn ?
                parsedData.atmosphericPressure + deviceOffset :
                parsedData.atmosphericPressure
                
                VStack(alignment: .center, spacing: 2) {
                    Text(String(format: "%.2f", correctedPressure))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
//                    if isOn && deviceOffset != 0 {
//                        Text("(\(deviceOffset > 0 ? "+" : "")\(String(format: "%.2f", deviceOffset)))")
//                            .font(.system(size: 10, weight: .light))
//                            .foregroundColor(.blue)
//                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    private var timeCell: some View {
        Text(formatTime(packet.timestamp))
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var calibrationStatusCell: some View {
        VStack {
            if offsetManager.isCalibrated(deviceId: packet.deviceID) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
