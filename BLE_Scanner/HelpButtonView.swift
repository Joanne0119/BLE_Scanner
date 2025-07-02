//
//  HelpButtonView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/6/29.
//  最後更新 2025/07/02

import SwiftUI

// 一個可重複使用的幫助按鈕，點擊後會以 Sheet 形式彈出指定的幫助內容。
struct HelpButtonView<Content: View>: View {
    @State private var isShowingHelpSheet = false
    
    // 要在彈出視窗中顯示的內容
    let helpContent: Content

    // - Parameter content: 一個閉包，返回要顯示的 View。
    init(@ViewBuilder content: () -> Content) {
        self.helpContent = content()
    }

    var body: some View {
        Button(action: {
            isShowingHelpSheet = true
        }) {
            Image(systemName: "questionmark.circle")
                .font(.title2) // 設定一個適中的大小
                .foregroundColor(.gray)
        }
        .sheet(isPresented: $isShowingHelpSheet) {
            // 彈出視窗的容器
            VStack(spacing: 0) {
                // 頂部標題和關閉按鈕
                HStack {
                    Text("說明")
                        .font(.headline)
                    Spacer()
                    Button(action: { isShowingHelpSheet = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                Divider()

                // 來自呼叫端的自訂內容
                ScrollView {
                    helpContent
                        .padding()
                }
                
                Spacer()
            }
            // 讓彈出視窗有圓角
            .cornerRadius(16)
        }
    }
}
