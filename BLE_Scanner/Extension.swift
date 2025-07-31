//
//  Extension.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/9.
//

import Foundation

extension Notification.Name {
    static let packetsUpdated = Notification.Name("packetsUpdated")
}

extension String {
    var cleanedHex: String {
        return self.components(separatedBy: .whitespacesAndNewlines).joined()
                   .components(separatedBy: CharacterSet(charactersIn: ",，")).joined()
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
