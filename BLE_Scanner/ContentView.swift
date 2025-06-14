//
//  ContentView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/11.
//  最後更新 2025/06/14
//

import SwiftUI

struct ContentView: View {
    @State private var maskSuggestions: [String] = UserDefaults.standard.savedMaskSuggestions
    @State private var dataSuggestions: [String] = UserDefaults.standard.savedDataSuggestions
    @StateObject var packetStore = SavedPacketsStore()
    var body: some View {
        TabView {
            BLEBroadcasterView(maskSuggestions: $maskSuggestions, dataSuggestions: $dataSuggestions)
                .tabItem {
                    Label("廣播", systemImage: "antenna.radiowaves.left.and.right")
                }

            BLEScannerView(packetStore: packetStore, maskSuggestions: $maskSuggestions)
                .tabItem {
                    Label("掃描", systemImage: "wave.3.right")
                }
            ScannerLogView(packetStore: packetStore)
                .tabItem {
                    Label("掃描Log", systemImage: "text.document")
                }
            SettingView(maskSuggestions: $maskSuggestions, dataSuggestions: $dataSuggestions)
                .tabItem {
                    Label("自訂輸入", systemImage: "rectangle.and.pencil.and.ellipsis")
                }
            PressureCorrectionView(maskSuggestions: $maskSuggestions)
                .tabItem {
                    Label("大氣壓力校正", systemImage: "checkmark.circle.badge.questionmark")
                }
        }
        .onChange(of: maskSuggestions) { newValue in
           UserDefaults.standard.savedMaskSuggestions = newValue
       }
       .onChange(of: dataSuggestions) { newValue in
           UserDefaults.standard.savedDataSuggestions = newValue
       }
    }
}

extension UserDefaults {
    private enum Keys {
        static let maskSuggestions = "maskSuggestions"
        static let dataSuggestions = "dataSuggestions"
    }

    var savedMaskSuggestions: [String] {
        get {
            array(forKey: Keys.maskSuggestions) as? [String] ?? []
        }
        set {
            set(newValue, forKey: Keys.maskSuggestions)
        }
    }

    var savedDataSuggestions: [String] {
        get {
            array(forKey: Keys.dataSuggestions) as? [String] ?? []
        }
        set {
            set(newValue, forKey: Keys.dataSuggestions)
        }
    }
}


#Preview {
    ContentView()
}
