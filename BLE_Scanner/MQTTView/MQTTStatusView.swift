//
//  MQTTStatusView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/20.
//  最後更新 2025/07/17
//
import SwiftUI

struct MQTTStatusView: View {
    @EnvironmentObject var mqttManager: MQTTManager
    
    @State private var isUpdating = false
    @State private var showUpdateSuccess = false
    @State private var isReconnecting = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 狀態指示燈 - 增強版
            ZStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                
                // 重連時顯示脈動效果
                if isReconnecting {
                    Circle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 15, height: 15)
                        .scaleEffect(isReconnecting ? 1.5 : 1.0)
                        .opacity(isReconnecting ? 0.0 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isReconnecting)
                }
            }
            .animation(.easeInOut, value: mqttManager.isConnected)

            // 狀態文字
            Text(statusText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // 按鈕區域
            HStack(spacing: 6) {
                // 手動更新按鈕（僅在已連接時顯示）
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
                }
                
                // 重連按鈕（在斷線時顯示）
                if !mqttManager.isConnected && !isReconnecting {
                    Button(action: {
                        forceReconnect()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                            
                            Text("重連")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(10)
        .shadow(radius: 5)
        .animation(.default, value: mqttManager.connectionStatus)
        .animation(.easeInOut(duration: 0.3), value: mqttManager.isConnected)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onChange(of: mqttManager.connectionStatus) { newStatus in
            // 監控重連狀態
            isReconnecting = newStatus.contains("重連中")
        }
    }
    
    // MARK: - 計算屬性
    private var connectionColor: Color {
        if isReconnecting {
            return .orange
        }
        return mqttManager.isConnected ? .green : .red
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
    
    // MARK: - 強制重連函數
    private func forceReconnect() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReconnecting = true
        }
        
        mqttManager.forceReconnect()
        
        // 重連動畫持續一段時間
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isReconnecting = false
            }
        }
    }
    
    // MARK: - 緩衝訊息計算
    private var statusText: String {
        if !mqttManager.isConnected && mqttManager.pendingMessageCount > 0 {
            return "\(mqttManager.connectionStatus) (\(mqttManager.pendingMessageCount) 則訊息待發送)"
        }
        return mqttManager.connectionStatus
    }
}

struct MQTTToolbarStatusView: View {
    @EnvironmentObject var mqttManager: MQTTManager
    @State private var isUpdating = false
    @State private var showUpdateSuccess = false
    @State private var isReconnecting = false
    
    var body: some View {
        Button(action: handleButtonTap) {
            ZStack {
                // 重連脈動效果
                if isReconnecting {
                    Circle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 30, height: 30)
                        .scaleEffect(isReconnecting ? 1.5 : 1.0)
                        .opacity(isReconnecting ? 0.0 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isReconnecting)
                }
                
                // 主要圖示
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if showUpdateSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isReconnecting {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(isReconnecting ? 360 : 0))
                        .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isReconnecting)
                } else {
                    Image(systemName: mqttManager.isConnected ? "checkmark.icloud" : "xmark.icloud")
                        .foregroundColor(mqttManager.isConnected ? .white : .red)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .frame(width: 20, height: 20, alignment: .center)
            .animation(.easeInOut(duration: 0.1), value: isUpdating)
            .animation(.easeInOut(duration: 0.1), value: showUpdateSuccess)
            .animation(.easeInOut(duration: 0.1), value: mqttManager.isConnected)
        }
        .disabled(isUpdating || isReconnecting)
        .onChange(of: mqttManager.isConnected) { newValue in
            print("MQTT 連接狀態變化: \(newValue)")
        }
        .onChange(of: mqttManager.connectionStatus) { newValue in
            print("MQTT 狀態訊息變化: \(newValue)")
            isReconnecting = newValue.contains("重連中")
        }
    }
    
    private func handleButtonTap() {
        if mqttManager.isConnected {
            manualUpdateData()
        } else {
            forceReconnect()
        }
    }
    
    private func manualUpdateData() {
        guard !isUpdating else { return }
        
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isUpdating = true
                self.showUpdateSuccess = false
            }
        }
        
        mqttManager.requestAllInitialData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isUpdating = false
                self.showUpdateSuccess = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showUpdateSuccess = false
                }
            }
        }
    }
    
    private func forceReconnect() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReconnecting = true
        }
        
        mqttManager.forceReconnect()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isReconnecting = false
            }
        }
    }
}
