//
//  ContentView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/4/11.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BLEBroadcasterView()
                .tabItem {
                    Label("廣播", systemImage: "antenna.radiowaves.left.and.right")
                }

            BLEScannerView()
                .tabItem {
                    Label("掃描", systemImage: "wave.3.right")
                }
        }
    }
}

#Preview {
    ContentView()
}
