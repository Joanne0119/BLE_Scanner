//
//  CompassManager.swift
//  BLE_Scanner
//
//  Created by 劉丞恩 on 2025/7/1.
//  最後更新 2025/07/04

import Foundation
import CoreLocation
import Combine

class CompassManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager: CLLocationManager?
    
    @Published var heading: Double = 0.0 // 度數，0 是北，90 是東

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.headingFilter = kCLHeadingFilterNone
        locationManager?.startUpdatingHeading()
        locationManager?.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.magneticHeading
        }
    }
}
