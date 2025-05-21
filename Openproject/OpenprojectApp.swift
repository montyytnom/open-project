//
//  OpenprojectApp.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
import UserNotifications
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set the notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions immediately
        requestNotificationPermissions()
        
        // Initialize the badge count to zero
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        print("!!! DEBUG_APP: Application did finish launching")
        consoleLog("Application did finish launching with options: \(String(describing: launchOptions))")
        ConsoleLog.info("AppDelegate initialized with OS logging")
        
        // Register for background refresh and processing
        registerBackgroundTasks()
        
        // If the app was launched from a notification, handle it
        if let notificationPayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("App launched from notification: \(notificationPayload)")
            handleNotification(notificationPayload)
        }
        
        // Also check for local notification launches
        if let localNotificationPayload = launchOptions?[UIApplication.LaunchOptionsKey.localNotification] as? UILocalNotification {
            print("App launched from local notification")
            if let userInfo = localNotificationPayload.userInfo {
                handleNotification(userInfo)
            }
        }
        
        // Check and refresh token if needed
        refreshTokenIfNeeded()
        
        return true
    }
    
    // Check and refresh token if close to expiration
    private func refreshTokenIfNeeded() {
        DispatchQueue.main.async {
            guard let appState = self.appState, appState.isLoggedIn else { return }
            
            // If token exists but is expired or will expire soon, refresh it
            if let expirationDate = appState.tokenExpirationDate {
                let timeUntilExpiration = expirationDate.timeIntervalSinceNow
                // Refresh if token will expire in less than 1 hour
                if timeUntilExpiration < 3600 {
                    print("Token will expire soon, refreshing...")
                    appState.refreshAccessToken { success in
                        if success {
                            print("Token refreshed on app launch")
                            // Preload data after refreshing token
                            self.preloadAppData()
                        } else {
                            print("Failed to refresh token on app launch")
                        }
                    }
                } else {
                    // Token is still valid, preload data
                    self.preloadAppData()
                }
            }
        }
    }
    
    // Preload app data after confirming valid authentication
    private func preloadAppData() {
        guard let appState = self.appState, appState.isLoggedIn else { return }
        
        // Fetch notifications and projects
        appState.fetchNotifications { success in
            // Handle completion if needed
        }
        appState.fetchProjects()
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("Received callback URL: \(url)")
        // Handle the authentication callback
        // The ASWebAuthenticationSession will automatically handle this
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to string
        let tokenParts = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        
        // Save device token for later use
        UserDefaults.standard.set(token, forKey: "deviceToken")
        
        // Send token to server if user is logged in
        if let appState = self.appState, appState.isLoggedIn {
            appState.registerDeviceToken(token)
        } else {
            // Cache token to register later when user logs in
            UserDefaults.standard.set(token, forKey: "pendingDeviceToken")
            print("Cached device token for later registration")
        }
        
        // Register for provisional notifications (iOS 12+)
        // This provides quiet notifications without requiring explicit user permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Error requesting provisional notifications: \(error)")
            } else {
                print("Provisional notification authorization: \(granted)")
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle incoming push notification
        print("Received remote notification: \(userInfo)")
        
        // Process the notification
        handleNotification(userInfo)
        
        // Refresh data in the background
        DispatchQueue.main.async {
            if let appState = self.appState, appState.isLoggedIn {
                // Verify token still valid before fetching
                if let expirationDate = appState.tokenExpirationDate, expirationDate > Date() {
                    // Token valid, fetch notifications
                    appState.fetchNotifications { success in
                        completionHandler(.newData)
                    }
                } else {
                    // Token expired, try to refresh it
                    appState.refreshAccessToken { success in
                        if success {
                            // Token refreshed, fetch notifications
                            appState.fetchNotifications { success in
                                completionHandler(.newData)
                            }
                        } else {
                            completionHandler(.failed)
                        }
                    }
                }
            } else {
                completionHandler(.noData)
            }
        }
    }
    
    // Background fetch handler
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("Background fetch triggered")
        
        DispatchQueue.main.async {
            // Fetch latest notifications in the background
            guard let appState = self.appState else {
                completionHandler(.failed)
                return
            }
            
            // Check if user is logged in
            guard appState.isLoggedIn, appState.accessToken != nil else {
                completionHandler(.noData)
                return
            }
            
            // Refresh token if needed
            if let expirationDate = appState.tokenExpirationDate, expirationDate < Date() {
                appState.refreshAccessToken { success in
                    if success {
                        self.fetchDataInBackground(appState: appState, completionHandler: completionHandler)
                    } else {
                        completionHandler(.failed)
                    }
                }
            } else {
                self.fetchDataInBackground(appState: appState, completionHandler: completionHandler)
            }
            
            // Schedule the next background check using local notifications
            appState.scheduleBackgroundNotificationCheck()
        }
    }
    
    private func fetchDataInBackground(appState: AppState, completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Count current notifications to detect if we got new ones
        let currentCount = appState.notifications.count
        let currentUnreadCount = appState.unreadNotificationCount
        
        appState.fetchNotifications { success in
            // Check if we got new notifications
            if appState.notifications.count > currentCount || appState.unreadNotificationCount > currentUnreadCount {
                completionHandler(.newData)
            } else {
                completionHandler(.noData)
            }
        }
    }
    
    private func registerBackgroundTasks() {
        // Register for background fetch
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        
        // Register background processing task
        let backgroundProcessingTaskId = "com.openproject.backgroundProcessing"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingTaskId, using: nil) { task in
            self.handleBackgroundProcessing(task: task as! BGProcessingTask)
        }
        
        // Register notification fetch task
        let fetchNotificationsTaskId = "com.openproject.fetchNotifications"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: fetchNotificationsTaskId, using: nil) { task in
            self.handleNotificationFetch(task: task as! BGProcessingTask)
        }
        
        print("Background tasks registered")
        
        // Schedule initial tasks
        scheduleBackgroundProcessing()
        scheduleNotificationFetch()
        
        // Register for silent notification category
        registerSilentNotificationCategory()
    }
    
    private func scheduleBackgroundProcessing() {
        let backgroundProcessingTaskId = "com.openproject.backgroundProcessing"
        let request = BGProcessingTaskRequest(identifier: backgroundProcessingTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Request execution no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background processing task scheduled")
        } catch {
            print("Could not schedule background processing: \(error)")
        }
    }
    
    private func scheduleNotificationFetch() {
        let fetchNotificationsTaskId = "com.openproject.fetchNotifications"
        let request = BGProcessingTaskRequest(identifier: fetchNotificationsTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Fetch notifications more frequently (every 5 minutes)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Notification fetch task scheduled")
        } catch {
            print("Could not schedule notification fetch: \(error)")
        }
    }
    
    private func handleBackgroundProcessing(task: BGProcessingTask) {
        // Schedule the next background processing task
        scheduleBackgroundProcessing()
        
        // Create a task expiration handler
        task.expirationHandler = {
            print("Background processing task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Check if user is logged in
        guard let appState = self.appState, appState.isLoggedIn else {
            task.setTaskCompleted(success: false)
            return
        }
        
        // Refresh token if needed
        if let expirationDate = appState.tokenExpirationDate, expirationDate < Date() {
            appState.refreshAccessToken { success in
                if success {
                    appState.fetchNotifications { success in
                        task.setTaskCompleted(success: true)
                    }
                } else {
                    task.setTaskCompleted(success: false)
                }
            }
        } else {
            appState.fetchNotifications { success in
                task.setTaskCompleted(success: true)
            }
        }
    }
    
    private func handleNotificationFetch(task: BGProcessingTask) {
        // Schedule next fetch
        scheduleNotificationFetch()
        
        // Set expiration handler
        task.expirationHandler = {
            print("Notification fetch task expired")
            task.setTaskCompleted(success: false)
        }
        
        print("Executing notification fetch in background")
        
        guard let appState = self.appState, appState.isLoggedIn else {
            print("Not logged in, can't fetch notifications")
            task.setTaskCompleted(success: false)
            return
        }
        
        // Check token validity
        if let expirationDate = appState.tokenExpirationDate {
            if expirationDate < Date() {
                // Token expired, refresh it
                appState.refreshAccessToken { success in
                    if success {
                        // Token refreshed, fetch notifications
                        appState.fetchNotifications { success in
                            // When complete, mark task as done
                            task.setTaskCompleted(success: true)
                        }
                    } else {
                        // Token refresh failed
                        print("Token refresh failed in background fetch")
                        task.setTaskCompleted(success: false)
                    }
                }
            } else {
                // Token valid, fetch notifications
                appState.fetchNotifications { success in
                    // When complete, mark task as done
                    task.setTaskCompleted(success: true)
                }
            }
        } else {
            // No token expiration date
            print("No token expiration date")
            task.setTaskCompleted(success: false)
        }
    }
    
    private func handleNotification(_ userInfo: [AnyHashable: Any]) {
        // Handle different notification types
        if let workPackageId = userInfo["workPackageId"] as? Int {
            print("Handling notification for work package: \(workPackageId)")
            // Navigate to work package
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenWorkPackage"),
                    object: workPackageId
                )
            }
        } else if let notificationId = userInfo["notificationId"] as? Int {
            print("Handling notification with ID: \(notificationId)")
            // Navigate to notifications tab
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenNotification"),
                    object: notificationId
                )
            }
        }
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Will present notification in foreground: \(notification.request.identifier)")
        
        // Show the notification even when app is in foreground with all options
        var options: UNNotificationPresentationOptions = [.banner, .sound]
        
        // Add badge if available on iOS 14+
        if #available(iOS 14.0, *) {
            options.insert(.badge)
        } else {
            // For older iOS versions, manually update the badge
            if let appState = self.appState {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = appState.unreadNotificationCount
                }
            }
        }
        
        // If the notification has a badge value, use it to update the app icon badge
        if let badgeNumber = notification.request.content.badge?.intValue {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badgeNumber
                print("Setting badge from notification to: \(badgeNumber)")
            }
        }
        
        completionHandler(options)
    }
    
    // Handle notification interactions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("Received notification response for action: \(response.actionIdentifier)")
        
        // Handle different actions
        switch response.actionIdentifier {
        case "VIEW_MENTION", "VIEW_UPDATE", "VIEW_NOTIFICATION", UNNotificationDefaultActionIdentifier:
            // Default action - view the notification
            handleNotification(userInfo)
            
        case "MARK_READ":
            // Mark as read action
            if let notificationId = userInfo["notificationId"] as? Int {
                print("Marking notification as read: \(notificationId)")
                // Mark the notification as read
                DispatchQueue.main.async {
                    self.appState?.markNotificationAsRead(id: notificationId)
                }
            }
            
        case UNNotificationDismissActionIdentifier:
            // Notification was dismissed, just log it
            print("Notification dismissed")
            
        default:
            print("Unknown action identifier: \(response.actionIdentifier)")
        }
        
        completionHandler()
    }
    
    private func requestNotificationPermissions() {
        // First check if we already have authorization
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("Current notification settings: \(settings.authorizationStatus.rawValue)")
                
                // If we already have authorization, just register
                if settings.authorizationStatus == .authorized || 
                   settings.authorizationStatus == .provisional {
                    print("Already authorized for notifications, registering...")
                    UIApplication.shared.registerForRemoteNotifications()
                    
                    // Make sure we have all notification categories registered
                    self.registerNotificationCategories()
                    return
                }
                
                // Otherwise, request authorization
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional, .criticalAlert]) { granted, error in
                    DispatchQueue.main.async {
                        if granted {
                            print("Notification permissions granted")
                            // For local notifications, we don't strictly need to register for remote notifications,
                            // but keeping this in case we add server push later
                            UIApplication.shared.registerForRemoteNotifications()
                            
                            // Register notification categories for different notification types
                            self.registerNotificationCategories()
                            
                            // Schedule a test notification to verify permissions
                            self.scheduleTestNotification()
                        } else if let error = error {
                            print("Error requesting notification permissions: \(error.localizedDescription)")
                        } else {
                            print("Notification permissions denied")
                        }
                    }
                }
            }
        }
    }
    
    private func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        
        // Category for mention notifications
        let mentionActions = [
            UNNotificationAction(
                identifier: "VIEW_MENTION",
                title: "View",
                options: .foreground
            ),
            UNNotificationAction(
                identifier: "MARK_READ",
                title: "Mark as Read",
                options: .destructive
            )
        ]
        let mentionCategory = UNNotificationCategory(
            identifier: "MENTION_CATEGORY",
            actions: mentionActions,
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Category for watched updates
        let watchedActions = [
            UNNotificationAction(
                identifier: "VIEW_UPDATE",
                title: "View Update",
                options: .foreground
            ),
            UNNotificationAction(
                identifier: "MARK_READ",
                title: "Mark as Read",
                options: .destructive
            )
        ]
        let watchedCategory = UNNotificationCategory(
            identifier: "WATCHED_CATEGORY",
            actions: watchedActions,
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Default category for other notifications
        let defaultActions = [
            UNNotificationAction(
                identifier: "VIEW_NOTIFICATION",
                title: "View",
                options: .foreground
            ),
            UNNotificationAction(
                identifier: "MARK_READ",
                title: "Mark as Read",
                options: .destructive
            )
        ]
        let defaultCategory = UNNotificationCategory(
            identifier: "DEFAULT_CATEGORY",
            actions: defaultActions,
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Register the categories
        center.setNotificationCategories([mentionCategory, watchedCategory, defaultCategory])
        print("Registered notification categories")
    }
    
    // Add a test notification to verify permissions
    private func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Notifications Enabled"
        content.body = "You will now receive notifications when new items appear in OpenProject"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "FOREGROUND_VISIBLE"
        
        // Update badge count
        if let appState = self.appState {
            content.badge = NSNumber(value: appState.unreadNotificationCount)
        }
        
        // Schedule for 5 seconds from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling test notification: \(error)")
            } else {
                print("Test notification scheduled successfully")
            }
        }
    }
    
    // Register a special category for silent background notifications
    private func registerSilentNotificationCategory() {
        let category = UNNotificationCategory(
            identifier: "BACKGROUND_REFRESH",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    // Application will become active
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("Application did become active - updating badge")
        
        // Update badge if we have unread notifications
        if let appState = self.appState {
            DispatchQueue.main.async {
                let count = appState.unreadNotificationCount
                UIApplication.shared.applicationIconBadgeNumber = count
                print("Setting badge on app active to: \(count)")
            }
        }
        
        // Refresh data when app becomes active
        DispatchQueue.main.async {
            self.appState?.fetchNotifications { success in
                // Handle completion if needed
            }
        }
        
        // Reset scheduled background tasks when app becomes active
        scheduleBackgroundProcessing()
        scheduleNotificationFetch()
        
        // Request notification permissions again if needed
        refreshNotificationPermissions()
    }
    
    // Refresh notification permissions if needed
    private func refreshNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("Current notification settings: \(settings.authorizationStatus.rawValue)")
                
                if settings.authorizationStatus == .notDetermined || 
                   settings.authorizationStatus == .denied {
                    // Prompt for permissions again
                    self.requestNotificationPermissions()
                } else if settings.authorizationStatus == .authorized || 
                          settings.authorizationStatus == .provisional {
                    // We have permission, just register again to be safe
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    // Application will resign active
    func applicationWillResignActive(_ application: UIApplication) {
        print("Application will resign active - ensuring badge is set")
        
        // Ensure badge count is set before app goes to background
        if let appState = self.appState {
            let count = appState.unreadNotificationCount
            UIApplication.shared.applicationIconBadgeNumber = count
            print("Setting badge before resign active: \(count)")
        }
    }
    
    // Application did enter background
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("Application did enter background")
        
        // Schedule background processing when app enters background
        scheduleBackgroundProcessing()
        
        // Update badge one more time to ensure it persists
        if let appState = self.appState {
            let count = appState.unreadNotificationCount
            UIApplication.shared.applicationIconBadgeNumber = count
            print("Setting badge on enter background: \(count)")
            
            // Create a test notification that should appear in background
            appState.checkForNewNotifications()
        }
    }
}

@main
struct OpenprojectApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Register the URL scheme programmatically if needed
        registerURLScheme()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // Pass the appState to the AppDelegate so it can handle notifications
                    appDelegate.appState = appState
                }
                .onOpenURL { url in
                    // This is called when app is opened via URL scheme
                    print("App opened with URL: \(url)")
                }
        }
    }
    
    private func registerURLScheme() {
        // This is just a placeholder - the URL scheme registration 
        // needs to be done in the Info.plist, which we did by creating a custom Info.plist
        print("App initialized with 'openproject' URL scheme")
    }
}
