// ContentView.swift

//  最後更新 2025/06/20
//

import SwiftUI

struct ContentView: View {
    @StateObject private var mqttManager: MQTTManager
    @StateObject private var packetStore: SavedPacketsStore
    @StateObject private var offsetManager: PressureOffsetManager
    
    init() {
        // 先建立 MQTTManager
        let manager = MQTTManager()
        // 再建立 SavedPacketsStore，並將 manager 傳入
        let store = SavedPacketsStore(mqttManager: manager)
        let pressureManager = PressureOffsetManager(mqttManager: manager)
        
        _mqttManager = StateObject(wrappedValue: manager)
        _packetStore = StateObject(wrappedValue: store)
        _offsetManager = StateObject(wrappedValue: pressureManager)
        
        setupNavigationBarAppearance()
    }
    
    private func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        // 設置返回按鈕顏色
        UINavigationBar.appearance().tintColor = UIColor.white
        
        // 應用到所有導航欄
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                
                BLEBroadcasterView(maskSuggestions: $mqttManager.maskSuggestions, dataSuggestions: $mqttManager.dataSuggestions)
                    .tabItem {
                        Label("廣播", systemImage: "antenna.radiowaves.left.and.right")
                    }
            
                BLEScannerView(packetStore: packetStore, maskSuggestions: $mqttManager.maskSuggestions)
                    .tabItem {
                        Label("掃描", systemImage: "wave.3.right")
                    }
                
                ScannerLogView(packetStore: packetStore)
                    .tabItem {
                        Label("掃描Log", systemImage: "text.document")
                    }
                // 將 mqttManager 作為環境物件傳遞下去
                SettingView()
                    .tabItem {
                        Label("自訂輸入", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                PressureCorrectionView(offsetManager: offsetManager, maskSuggestions: $mqttManager.maskSuggestions)
                    .tabItem {
                        Label("大氣壓力校正", systemImage: "checkmark.circle.badge.questionmark")
                    }
            }
            
            if !mqttManager.connectionStatus.isEmpty {
                MQTTStatusView()
                    .padding(.bottom, 50)
                    .padding(.trailing, 20)
            }
        }
        .environmentObject(packetStore)
        .environmentObject(mqttManager)
        .environmentObject(offsetManager)
        .onAppear {
            offsetManager.loadAndSyncOffsets()
            // 當 View 出現時，開始 MQTT 連線
            mqttManager.connect()
        }
    }
}

#Preview {
    ContentView()
}
