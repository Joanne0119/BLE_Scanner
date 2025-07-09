//
//  ContentView.swift
//  WatchBLE Watch App
//
//  Created by 劉丞恩 on 2025/7/9.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BLEWatchScannerView()
            
            WatchScannerListView()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
