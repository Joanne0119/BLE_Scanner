//
//  MQTTStatusView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/20.
//  最後更新 2025/07/02
//
import SwiftUI

struct MQTTStatusView: View {
    // 使用 @EnvironmentObject 來從環境中獲取共享的 MQTTManager 實例
    @EnvironmentObject var mqttManager: MQTTManager
    
    // 狀態變數追蹤更新狀態
    @State private var isUpdating = false
    @State private var showUpdateSuccess = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 狀態指示燈
            Circle()
                .fill(mqttManager.isConnected ? .green : .red)
                .frame(width: 10, height: 10)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                .animation(.easeInOut, value: mqttManager.isConnected)

            // 狀態文字
            Text(mqttManager.connectionStatus)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            // 手動更新按鈕
            if mqttManager.isConnected {
                Button(action: {
                    manualUpdateData()
                }) {
                    HStack(spacing: 4) {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: showUpdateSuccess ? "checkmark.circle.fill" : "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(showUpdateSuccess ? .green : .white)
                        }
                        
                        if !isUpdating {
                            Text(showUpdateSuccess ? "已更新" : "更新")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(showUpdateSuccess ? .green : .white)
                        }
                    }
                }
                .disabled(isUpdating)
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(isUpdating ? 0.1 : 0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .scaleEffect(isUpdating ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isUpdating)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(10)
        .shadow(radius: 5)
        .animation(.default, value: mqttManager.connectionStatus)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    // MARK: - 手動更新資料函數
    private func manualUpdateData() {
        guard !isUpdating else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isUpdating = true
            showUpdateSuccess = false
        }
        
        // 觸發所有資料更新
        mqttManager.requestAllInitialData()
        
        // 模擬更新完成後的回饋
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isUpdating = false
                showUpdateSuccess = true
            }
            
            // 成功狀態顯示 2 秒後恢復正常
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showUpdateSuccess = false
                }
            }
        }
    }
}

struct MQTTToolbarStatusView: View {
    @EnvironmentObject var mqttManager: MQTTManager
    @State private var isUpdating = false
    @State private var showUpdateSuccess = false

    var body: some View {
        Button(action: handleButtonTap) {
            // 使用 ZStack 來確保 ProgressView 和 Image 佔用相同空間，防止版面跳動
            ZStack {
                // 根據不同狀態顯示對應的圖示
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8) // 調整大小以適應 Toolbar
                } else if showUpdateSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if mqttManager.isConnected {
                    Image(systemName: "checkmark.icloud")
                        .foregroundColor(.white) // 使用主題色或 .blue
                } else {
                    Image(systemName: "xmark.icloud")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 16, weight: .medium)) // 統一設定字體大小和粗細
            .frame(width: 20, height: 20, alignment: .center) // 給予固定大小，防止切換時佈局變化
            .animation(.easeInOut(duration: 0.2), value: isUpdating)
            .animation(.easeInOut(duration: 0.2), value: showUpdateSuccess)
            .animation(.easeInOut(duration: 0.2), value: mqttManager.isConnected)
        }
        .disabled(isUpdating)
    }
    
    private func handleButtonTap() {
        if mqttManager.isConnected {
            // 如果已連線，則執行手動更新
            manualUpdateData()
        } else {
            // 如果未連線，則嘗試重新連線
            mqttManager.connect()
        }
    }
    
    
    // 更新資料的邏輯與原本的 MQTTStatusView 相同
    private func manualUpdateData() {
        guard !isUpdating else { return }
        
        withAnimation {
            isUpdating = true
            showUpdateSuccess = false
        }
        
        mqttManager.requestAllInitialData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isUpdating = false
                showUpdateSuccess = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showUpdateSuccess = false
                }
            }
        }
    }
}
