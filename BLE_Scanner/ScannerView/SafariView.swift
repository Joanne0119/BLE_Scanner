//
//  SafariView.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/17.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    @Binding var loadFailed: Bool
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = context.coordinator
        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView
        
        init(_ parent: SafariView) {
            self.parent = parent
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.isPresented = false
        }
        
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            DispatchQueue.main.async {
                if !didLoadSuccessfully {
                    print("Safari view failed to load")
                    self.parent.loadFailed = true
                }
            }
        }
    }
}

// MARK: - 錯誤顯示視圖
struct ChartLoadErrorView: View {
    @Binding var isPresented: Bool
    let url: String
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 錯誤圖示
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                
                // 錯誤訊息
                VStack(spacing: 10) {
                    Text("無法載入圖表")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("請檢查網路連線或稍後再試")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 按鈕區域
                VStack(spacing: 15) {
                    // 重試按鈕
                    Button(action: {
                        isPresented = false
                        // 可以在這裡觸發重新載入
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isPresented = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重試")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    // 用外部瀏覽器開啟
                    Button(action: {
                        if let url = URL(string: url) {
                            UIApplication.shared.open(url)
                        }
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("用瀏覽器開啟")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // 關閉按鈕
                    Button("關閉") {
                        isPresented = false
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray)
                    .padding()
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("載入錯誤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
