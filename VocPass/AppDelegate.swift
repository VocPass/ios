//
//  AppDelegate.swift
//  VocPass
//
//  處理一般推播通知：註冊 APNs、接收通知後啟動 Live Activity。
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("⚡ [Push] 通知授權失敗: \(error)") }
            print("⚡ [Push] 通知授權: \(granted)")
        }
        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }
        return true
    }

    // MARK: - APNs Device Token

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("⚡ [Push] APNs Device Token: \(hex)")
        Task { @MainActor in
            DynamicIslandService.shared.apnsDeviceTokenHex = hex
            DynamicIslandService.shared.uploadTokensToServer()
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚡ [Push] APNs 註冊失敗: \(error)")
    }

    // MARK: - 前景收到通知（顯示 banner）

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        handleNotification(userInfo: userInfo)
        completionHandler([.banner, .sound])
    }

    // MARK: - 點擊通知

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        handleNotification(userInfo: userInfo)
        completionHandler()
    }

    // MARK: - 背景收到 silent push / content-available

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        handleNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    // MARK: - 處理通知

    private func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let action = userInfo["action"] as? String else { return }

        Task { @MainActor in
            let di = DynamicIslandService.shared
            switch action {
            case "start_live_activity":
                if !di.isActivityRunning {
                    await di.startActivity()
                }
            case "stop_live_activity":
                di.endActivity()
            default:
                break
            }
        }
    }
}
