//
//  AppDelegate.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var notificationHandler: NotificationActionHandler?

    func configure(services: AppServices) {
        notificationHandler = NotificationActionHandler(services: services)
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Regular reminders are silent in foreground since the user already sees their state on screen.
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let handler = notificationHandler else {
            completionHandler()
            return
        }

        Task { @MainActor in
            await handler.handle(response: response)
            completionHandler()
        }
    }
}
