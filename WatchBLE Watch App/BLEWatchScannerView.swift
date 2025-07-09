//
//  BLEWatchScannerView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//

import SwiftUI

struct BLEWatchScannerView: View {
    @StateObject private var scanner = CBLEScanner()
    @State private var isScanning = false
    
    // 用於控制動畫的狀態變數
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // 設置一個深色背景，讓白色元件更突出
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isScanning {
                scanningView
            } else {
                initialView
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    var initialView: some View {
        Button(action: {
            scanner.shouldStopScan = true
            scanner.expectedMaskText = "FFFFFFFFFFFFFFFFFFFFFFFFFF"
            scanner.startScanning()
            
            withAnimation(.spring()) {
                isScanning = true
            }
        }) {
            VStack(spacing: 15) {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue.opacity(0.85))
                    .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 0)
                
                Text("點擊一下來掃描")
                    .font(.headline)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }
        
    var scanningView: some View {
        // 將整個掃描畫面變成一個按鈕
        Button(action: {
            // --- 停止掃描 ---
            scanner.stopScanning()
            isAnimating = false
            
            withAnimation(.easeOut(duration: 0.2)) {
                isScanning = false
            }
        }) {
            VStack(spacing: 15) {
                Spacer()
                
                // --- 動畫圖示 ---
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 100)) // 讓動畫圖示大一點
                    .foregroundColor(.blue)
                    // 根據 isAnimating 狀態在 1.0 和 1.2 之間縮放
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .shadow(color: .blue.opacity(0.7), radius: isAnimating ? 20 : 10)
                
                Text("掃描中...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("點擊任一處可停止")
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                Spacer()
            }
        }
        .onAppear(perform: startAnimation)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    // --- 控制動畫的函式 ---
    func startAnimation() {
        // 使用一個會永遠重複的動畫來改變 isAnimating 狀態
        // 這會觸發 scaleEffect 和 shadow 的變化，產生脈動效果
        withAnimation(.easeInOut(duration: 1.2).repeatForever()) {
            isAnimating = true
        }
    }
}


#Preview {
    BLEWatchScannerView()
}
