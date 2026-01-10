//
//  WatchDogNotificationService.swift
//  HashRipper
//
//  System notifications for WatchDog events
//

import Foundation
import UserNotifications
import AppKit

/// Service to send macOS system notifications for WatchDog events
@MainActor
class WatchDogNotificationService {
    static let shared = WatchDogNotificationService()
    
    private init() {
        requestNotificationPermission()
    }
    
    // MARK: - Permission
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }
    
    // MARK: - WatchDog Notifications
    
    /// Send notification when WatchDog restarts a miner
    func notifyMinerRestarted(minerName: String, reason: String) {
        guard AppSettings.shared.areWatchdogNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Miner Restarted"
        content.subtitle = minerName
        content.body = reason
        content.sound = .default
        content.categoryIdentifier = "WATCHDOG_RESTART"
        
        let request = UNNotificationRequest(
            identifier: "watchdog-restart-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send restart notification: \(error)")
            }
        }
    }
    
    /// Send notification when a miner goes offline
    func notifyMinerOffline(minerName: String, ipAddress: String) {
        guard AppSettings.shared.areWatchdogNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Miner Offline"
        content.subtitle = minerName
        content.body = "Unable to connect to \(ipAddress)"
        content.sound = .default
        content.categoryIdentifier = "WATCHDOG_OFFLINE"
        
        let request = UNNotificationRequest(
            identifier: "watchdog-offline-\(minerName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send offline notification: \(error)")
            }
        }
    }
    
    /// Send notification for pool alert
    func notifyPoolAlert(minerName: String, poolIdentifier: String) {
        guard AppSettings.shared.areWatchdogNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Pool Alert"
        content.subtitle = minerName
        content.body = "Unapproved pool detected: \(poolIdentifier)"
        content.sound = .default
        content.categoryIdentifier = "WATCHDOG_POOL_ALERT"
        
        let request = UNNotificationRequest(
            identifier: "watchdog-pool-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send pool alert notification: \(error)")
            }
        }
    }
    
    /// Send notification when miner comes back online
    func notifyMinerBackOnline(minerName: String) {
        guard AppSettings.shared.areWatchdogNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Miner Online"
        content.subtitle = minerName
        content.body = "Connection restored"
        content.sound = nil // No sound for recovery - less disruptive
        content.categoryIdentifier = "WATCHDOG_ONLINE"
        
        let request = UNNotificationRequest(
            identifier: "watchdog-online-\(minerName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send online notification: \(error)")
            }
        }
    }
}
