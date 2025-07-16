//
//  TestSessionManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/07/16.
//

import Foundation

class TestSessionManager {
    // 使用單例模式，確保整個 App 只有一個實例
    static let shared = TestSessionManager()

    private var currentTestID: String
    private var lastActivityDate: Date

    // 私有化初始化方法，防止外部創建新實例
    private init() {
        self.currentTestID = TestSessionManager.generateNewID()
        self.lastActivityDate = Date()
        print("TestSessionManager 初始化，新的測試 ID: \(self.currentTestID)")
    }

    // 產生一個新的、基於時間的唯一 ID
    private static func generateNewID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    // 獲取當前的測試 ID，並檢查是否超時
    func getCurrentTestID() -> String {
        let now = Date()
        // 檢查距離上次活動是否超過 30 分鐘 (1800 秒)
        if now.timeIntervalSince(lastActivityDate) > 1800 {
            print("--- 超過30分鐘未活動，自動開始新的測試 ---")
            startNewTestSession()
        }
        // 更新最後活動時間
        lastActivityDate = now
        return currentTestID
    }

    // 強制開始一個新的測試會話
    func startNewTestSession() {
        self.currentTestID = TestSessionManager.generateNewID()
        self.lastActivityDate = Date()
        print("--- 已手動或自動開始新的測試會話 ---")
        print("新的測試 ID: \(self.currentTestID)")
    }
}
