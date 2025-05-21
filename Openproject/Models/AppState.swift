//
//  AppState.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
import WebKit

class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var user: User?
    @Published var currentProject: Project?
    @Published var projects: [Project] = []
    @Published var notifications: [Notification] = []
    @Published var unreadNotificationCount: Int = 0 {
        didSet {
            // Update the badge count when unreadNotificationCount changes
            print("Setting badge count: \(self.unreadNotificationCount)")
            
            // Use the recommended notification center API for badge count in iOS 17+
            UNUserNotificationCenter.current().setBadgeCount(Int(self.unreadNotificationCount)) { error in
                if let error = error {
                    print("Error setting badge count: \(error)")
                }
            }
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var customFields: [CustomField] = []
    @Published var isLoadingCustomFields: Bool = false
    @Published var reminderManager = ReminderManager()
    
    // Navigation state
    @Published var selectedWorkPackageId: Int?
    @Published var navigateTo: NavigationDestination?
    
    // OAuth configuration
    let clientId: String = "llOSDQiyoVOVerbyZT1yOzEHGQDigEAGsCr-hoGKo5o" // Same as working example
    let clientSecret: String = "ysHodvqAtwiljAUSpeqEavqR1rMYPRqTnwP6UxnkzUU" // Same as working example
    var accessToken: String?
    var refreshToken: String?
    var tokenExpirationDate: Date?
    
    // API Base URL
    var apiBaseURL: String = "https://your-openproject-instance.com/api/v3"
    var oauthBaseURL: String = "https://your-openproject-instance.com/oauth"
    
    // Helper method to construct valid API URLs
    func constructApiUrl(path: String) -> String {
        // If it's already a complete URL, return it
        if path.lowercased().hasPrefix("http") {
            return path
        }
        
        // Get base URL without trailing slash
        let baseURLWithoutTrailingSlash = apiBaseURL.hasSuffix("/") 
            ? String(apiBaseURL.dropLast())
            : apiBaseURL
            
        // If the path contains "/api/v3" and the base URL already includes it, remove from path
        var normalizedPath = path
        if normalizedPath.contains("/api/v3") && baseURLWithoutTrailingSlash.contains("/api/v3") {
            print("Removing duplicate /api/v3 from path: \(normalizedPath)")
            normalizedPath = normalizedPath.replacingOccurrences(of: "/api/v3", with: "")
        }
        
        // Make sure path starts with /
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/\(normalizedPath)"
        }
        
        let finalUrl = "\(baseURLWithoutTrailingSlash)\(normalizedPath)"
        print("Constructed API URL: \(finalUrl) from base: \(baseURLWithoutTrailingSlash) and path: \(path)")
        return finalUrl
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var notificationUpdateTimer: Timer?
    private var lastNotificationId: Int64 = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    init() {
        // Load user data immediately on initialization
        loadUserData()
        
        // Set up token refresh timer
        setupTokenRefreshTimer()
        
        // Setup timer for periodic notification checks
        setupNotificationTimer()
    }
    
    private func loadUserData() {
        if let token = KeychainHelper.standard.read(service: "openproject", account: "accessToken", type: String.self) {
            self.accessToken = token
            
            if let refreshToken = KeychainHelper.standard.read(service: "openproject", account: "refreshToken", type: String.self),
               let expirationDate = KeychainHelper.standard.read(service: "openproject", account: "tokenExpiration", type: Date.self),
               let userData = KeychainHelper.standard.read(service: "openproject", account: "userData", type: Data.self) {
                
                self.refreshToken = refreshToken
                self.tokenExpirationDate = expirationDate
                
                if let user = try? JSONDecoder().decode(User.self, from: userData) {
                    self.user = user
                    self.isLoggedIn = true
                    
                    // Load projects and notifications
                    fetchProjects()
                    fetchNotifications()
                }
            }
        }
    }
    
    // Save user data more securely to prevent token loss
    func saveUserData() {
        if let token = accessToken {
            KeychainHelper.standard.save(token, service: "openproject", account: "accessToken")
            
            if let refreshToken = refreshToken,
               let expirationDate = tokenExpirationDate,
               let user = user {
                
                KeychainHelper.standard.save(refreshToken, service: "openproject", account: "refreshToken")
                KeychainHelper.standard.save(expirationDate, service: "openproject", account: "tokenExpiration")
                
                // Only encode user data if needed
                if let userData = try? JSONEncoder().encode(user) {
                    KeychainHelper.standard.save(userData, service: "openproject", account: "userData")
                }
                
                // Save login status to UserDefaults for quick checking
                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                
                // Save API and OAuth URLs
                UserDefaults.standard.set(apiBaseURL, forKey: "apiBaseURL")
                UserDefaults.standard.set(oauthBaseURL, forKey: "oauthBaseURL")
                
                // Register any pending device token after successful login
                if let pendingToken = UserDefaults.standard.string(forKey: "pendingDeviceToken") {
                    registerDeviceToken(pendingToken)
                    UserDefaults.standard.removeObject(forKey: "pendingDeviceToken")
                }
            }
        }
    }
    
    func logout() {
        // Clear keychain credentials
        KeychainHelper.standard.delete(service: "openproject", account: "accessToken")
        KeychainHelper.standard.delete(service: "openproject", account: "refreshToken")
        KeychainHelper.standard.delete(service: "openproject", account: "tokenExpiration")
        KeychainHelper.standard.delete(service: "openproject", account: "userData")
        
        // Clear UserDefaults login state
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
        
        // Clear state variables
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        user = nil
        projects = []
        notifications = []
        isLoggedIn = false
        
        #if os(iOS)
        // Clear browser session data
        URLCache.shared.removeAllCachedResponses()
        
        if let websiteDataStore = WKWebsiteDataStore.default() as? WKWebsiteDataStore {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let dateFrom = Date(timeIntervalSince1970: 0)
            websiteDataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) { 
                print("Cleared all website data")
            }
        }
        #endif
    }
    
    // API Methods
    func fetchProjects() {
        guard let accessToken = self.accessToken else {
            print("No access token available")
            return
        }
        
        print("Will fetch projects with access token: \(accessToken.prefix(10))...")
        isLoading = true
        errorMessage = nil
        
        let urlString = "\(apiBaseURL)/projects"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL: \(urlString)"
            self.isLoading = false
            return
        }
        
        print("Fetching projects from: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            let workItem = DispatchWorkItem {
                self.isLoading = false
                
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid HTTP response")
                    self.errorMessage = "Invalid HTTP response"
                    return
                }
                
                print("HTTP Status Code: \(httpResponse.statusCode)")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    self.errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    self.errorMessage = "No data received"
                    return
                }
                
                print("Data received: \(data.count) bytes")
                
                // Debug: Print first 200 characters of response
                if let responseString = String(data: data, encoding: .utf8) {
                    let previewLength = min(500, responseString.count)
                    let preview = responseString.prefix(previewLength)
                    print("Response preview: \(preview)...")
                    
                    // Debug: Print the full structure of the first project
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let embedded = json["_embedded"] as? [String: Any],
                       let elements = embedded["elements"] as? [[String: Any]],
                       let firstProject = elements.first {
                        do {
                            let projectData = try JSONSerialization.data(withJSONObject: firstProject, options: .prettyPrinted)
                            if let prettyPrintedString = String(data: projectData, encoding: .utf8) {
                                print("FIRST PROJECT FULL STRUCTURE:")
                                print(prettyPrintedString)
                            }
                        } catch {
                            print("Error pretty-printing project: \(error)")
                        }
                    }
                }
                
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let embedded = json["_embedded"] as? [String: Any],
                          let elements = embedded["elements"] as? [[String: Any]] else {
                        print("Invalid JSON structure")
                        self.errorMessage = "Invalid JSON structure"
                        return
                    }
                    
                    var projects: [Project] = []
                    
                    for element in elements {
                        guard let id = element["id"] as? Int,
                              let name = element["name"] as? String,
                              let identifier = element["identifier"] as? String,
                              let links = element["_links"] as? [String: Any] else {
                            continue
                        }
                        
                        let description = element["description"] as? [String: Any]
                        let descriptionText = description?["raw"] as? String
                        let descriptionFormat = description?["format"] as? String
                        let descriptionHtml = description?["html"] as? String
                        
                        // Create ProjectDescription if available
                        var projectDescription: ProjectDescription? = nil
                        if let format = descriptionFormat, let raw = descriptionText, let html = descriptionHtml {
                            projectDescription = ProjectDescription(format: format, raw: raw, html: html)
                        }
                        
                        // Default dates if not available
                        let createdAt = element["createdAt"] as? String ?? "2023-01-01T00:00:00Z"
                        let updatedAt = element["updatedAt"] as? String ?? "2023-01-01T00:00:00Z"
                        
                        // Extract custom fields if present
                        let customFields: [String: Any] = element["customFields"] as? [String: Any] ?? [:]
                        
                        // Extract status explanation if present
                        var statusExplanation: ProjectDescription? = nil
                        if let explanation = element["statusExplanation"] as? [String: Any],
                           let format = explanation["format"] as? String,
                           let raw = explanation["raw"] as? String,
                           let html = explanation["html"] as? String {
                            statusExplanation = ProjectDescription(format: format, raw: raw, html: html)
                        }
                        
                        // Handle customField1 (Notes) if present
                        var customField1: ProjectDescription? = nil
                        // First check direct customField1 object (newer API format)
                        if let customField = element["customField1"] as? [String: Any],
                           let format = customField["format"] as? String,
                           let raw = customField["raw"] as? String, 
                           let html = customField["html"] as? String {
                            customField1 = ProjectDescription(format: format, raw: raw, html: html)
                        } 
                        // Then check inside customFields object (older API format)
                        else if let customField = customFields["customField1"] as? [String: Any],
                           let format = customField["format"] as? String,
                           let raw = customField["raw"] as? String, 
                           let html = customField["html"] as? String {
                            customField1 = ProjectDescription(format: format, raw: raw, html: html)
                        }
                        
                        // Handle customField2 (Materials) if present
                        var customField2: ProjectDescription? = nil
                        // First check direct customField2 object (newer API format)
                        if let customField = element["customField2"] as? [String: Any],
                           let format = customField["format"] as? String,
                           let raw = customField["raw"] as? String, 
                           let html = customField["html"] as? String {
                            customField2 = ProjectDescription(format: format, raw: raw, html: html)
                        } 
                        // Then check inside customFields object (older API format)
                        else if let customField = customFields["customField2"] as? [String: Any],
                           let format = customField["format"] as? String,
                           let raw = customField["raw"] as? String, 
                           let html = customField["html"] as? String {
                            customField2 = ProjectDescription(format: format, raw: raw, html: html)
                        }
                        
                        // Default link if extraction fails
                        let defaultLink = Link(href: "", title: nil, templated: nil, method: nil)
                        
                        // Extract all links from links section
                        let status = self.extractLink(from: links, key: "status")
                        let customField3 = self.extractLink(from: links, key: "customField3")
                        let customField1Link = self.extractLink(from: links, key: "customField1")
                        let customField2Link = self.extractLink(from: links, key: "customField2")
                        let customField6Link = self.extractLink(from: links, key: "customField6")
                        
                        // Create project instance
                        let project = Project(
                            id: id,
                            identifier: identifier,
                            name: name,
                            active: element["active"] as? Bool ?? true,
                            isPublic: element["public"] as? Bool ?? false,
                            description: projectDescription,
                            createdAt: createdAt,
                            updatedAt: updatedAt,
                            statusExplanation: statusExplanation,
                            customField1: customField1,
                            customField2: customField2,
                            customField6: nil,
                            links: ProjectLinks(
                                selfLink: self.extractLink(from: links, key: "self") ?? defaultLink,
                                createWorkPackage: self.extractLink(from: links, key: "createWorkPackage"),
                                createWorkPackageImmediately: self.extractLink(from: links, key: "createWorkPackageImmediately"),
                                workPackages: self.extractLink(from: links, key: "workPackages"),
                                storages: nil,
                                categories: self.extractLink(from: links, key: "categories"),
                                versions: nil,
                                memberships: nil,
                                types: self.extractLink(from: links, key: "types"),
                                update: nil,
                                updateImmediately: nil,
                                delete: self.extractLink(from: links, key: "delete"),
                                schema: nil,
                                status: status,
                                customField1: customField1Link,
                                customField2: customField2Link,
                                customField3: customField3,
                                customField6: customField6Link,
                                ancestors: nil,
                                projectStorages: nil,
                                parent: nil
                            )
                        )
                        
                        projects.append(project)
                    }
                    
                    self.projects = projects
                    print("Projects parsed successfully: \(projects.count)")
                } catch {
                    print("JSON parsing error: \(error)")
                    self.errorMessage = "JSON parsing error: \(error)"
                }
            }
            
            DispatchQueue.main.async(execute: workItem)
        }
        
        task.resume()
    }
    
    private func extractLink(from links: [String: Any], key: String) -> Link? {
        if let linkDict = links[key] as? [String: Any],
           let href = linkDict["href"] as? String {
            return Link(
                href: href,
                title: linkDict["title"] as? String,
                templated: linkDict["templated"] as? Bool,
                method: linkDict["method"] as? String
            )
        }
        return nil
    }
    
    func fetchNotifications(_ completion: ((Bool) -> Void)? = nil) {
        guard let accessToken = accessToken, isLoggedIn else {
            print("No access token available or not authenticated")
            self.isLoading = false
            completion?(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        print("Fetching notifications...")
        
        let urlString = "\(apiBaseURL)/notifications"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL: \(urlString)"
            self.isLoading = false
            completion?(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion?(false)
                return
            }
            
            // Process data on background thread first
            if let error = error {
                print("Error fetching notifications: \(error.localizedDescription)")
                self.updateNotificationState(
                    isLoading: false,
                    errorMessage: "Failed to load notifications: \(error.localizedDescription)",
                    notifications: nil,
                    completion: { completion?(false) }
                )
                return
            }
            
            guard let data = data else {
                print("No data received for notifications")
                self.updateNotificationState(
                    isLoading: false,
                    errorMessage: "No notification data received",
                    notifications: nil,
                    completion: { completion?(false) }
                )
                return
            }
            
            // Debug: Print response preview
            if let responseString = String(data: data, encoding: .utf8) {
                let previewLength = min(200, responseString.count)
                print("Notifications response preview: \(responseString.prefix(previewLength))...")
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let embedded = json["_embedded"] as? [String: Any],
                      let elements = embedded["elements"] as? [[String: Any]] else {
                    print("Invalid JSON structure for notifications")
                    self.updateNotificationState(
                        isLoading: false,
                        errorMessage: "Invalid notification data format",
                        notifications: nil,
                        completion: { completion?(false) }
                    )
                    return
                }
                
                var notifications: [Notification] = []
                
                for element in elements {
                    guard let id = element["id"] as? Int else { continue }
                    
                    // Extract notification links
                    let links = element["_links"] as? [String: Any] ?? [:]
                    
                    // Create a NotificationLinks object with properly extracted links
                    let notificationLinks = NotificationLinks(
                        actor: self.extractLink(from: links, key: "actor") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        project: self.extractLink(from: links, key: "project") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        resource: self.extractLink(from: links, key: "resource") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        activity: self.extractLink(from: links, key: "activity") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        readIAN: self.extractLink(from: links, key: "readIAN") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        unreadIAN: self.extractLink(from: links, key: "unreadIAN") ?? Link(href: "", title: nil, templated: nil, method: nil)
                    )
                    
                    // Process notification data
                    let notification = Notification(
                        id: id,
                        reason: element["reason"] as? String ?? "",
                        readIAN: element["readIAN"] as? Bool ?? false,
                        message: element["message"] as? String,
                        resourceType: element["resourceType"] as? String,
                        resourceId: element["resourceId"] as? Int,
                        resourceName: element["resourceName"] as? String,
                        createdAt: element["createdAt"] as? String ?? "",
                        updatedAt: element["updatedAt"] as? String,
                        links: notificationLinks
                    )
                    
                    notifications.append(notification)
                }
                
                self.updateNotificationState(
                    isLoading: false,
                    errorMessage: nil,
                    notifications: notifications,
                    completion: { completion?(true) }
                )
            } catch {
                print("Error processing notifications: \(error)")
                self.updateNotificationState(
                    isLoading: false,
                    errorMessage: "Error processing notifications: \(error.localizedDescription)",
                    notifications: nil,
                    completion: { completion?(false) }
                )
            }
        }.resume()
    }
    
    // Helper method to update notifications state safely on the main thread
    private func updateNotificationState(
        isLoading: Bool,
        errorMessage: String?,
        notifications: [Notification]?,
        completion: @escaping () -> Void
    ) {
        // Ensure updates happen on main thread
        if Thread.isMainThread {
            self.isLoading = isLoading
            self.errorMessage = errorMessage
            
            if let notifications = notifications {
                // Store old notifications for comparison
                let oldNotifications = self.notifications
                
                // Update notifications
                self.notifications = notifications
                
                // Update unread count
                let unreadCount = notifications.filter { !$0.readIAN }.count
                self.unreadNotificationCount = unreadCount
                
                // Update badge count on the app icon
                UNUserNotificationCenter.current().setBadgeCount(Int(self.unreadNotificationCount)) { error in
                    if let error = error {
                        print("Error setting badge count: \(error)")
                    }
                }
                
                // Check for new notifications that need push notification
                checkForNewNotificationsToAlert(oldNotifications: oldNotifications, newNotifications: notifications)
            }
            
            completion()
        } else {
            DispatchQueue.main.sync {
                self.isLoading = isLoading
                self.errorMessage = errorMessage
                
                if let notifications = notifications {
                    // Store old notifications for comparison
                    let oldNotifications = self.notifications
                    
                    // Update notifications
                    self.notifications = notifications
                    
                    // Update unread count
                    let unreadCount = notifications.filter { !$0.readIAN }.count
                    self.unreadNotificationCount = unreadCount
                    
                    // Update badge count on the app icon
                    UNUserNotificationCenter.current().setBadgeCount(Int(self.unreadNotificationCount)) { error in
                        if let error = error {
                            print("Error setting badge count: \(error)")
                        }
                    }
                    
                    // Check for new notifications that need push notification
                    checkForNewNotificationsToAlert(oldNotifications: oldNotifications, newNotifications: notifications)
                }
                
                completion()
            }
        }
    }
    
    // Helper method to detect new notifications that need local push notifications
    private func checkForNewNotificationsToAlert(oldNotifications: [Notification], newNotifications: [Notification]) {
        // Get IDs of old notifications
        let oldIds = Set(oldNotifications.map { $0.id })
        
        // Find notifications that are new and unread
        let newUnreadNotifications = newNotifications.filter { notification in
            return !oldIds.contains(notification.id) && !notification.readIAN
        }
        
        // Create local push notifications for mentions and watched updates
        for notification in newUnreadNotifications {
            // Check if this is a mention or watched update notification
            if notification.reason == "mentioned" || notification.reason == "watched" {
                createLocalNotification(for: notification)
                print("Created local push notification for \(notification.reason) notification: \(notification.id)")
            }
        }
    }
    
    func createLocalNotification(for notification: Notification) {
        let content = UNMutableNotificationContent()
        
        // Make title more specific based on notification reason
        switch notification.reason {
        case "mentioned":
            content.title = "You were mentioned"
            if let resourceName = notification.resourceName {
                content.subtitle = "in \(resourceName)"
            }
            // Set category for mentions
            content.categoryIdentifier = "MENTION_CATEGORY"
        case "watched":
            content.title = "Watched item updated"
            if let resourceName = notification.resourceName {
                content.subtitle = resourceName
            }
            // Set category for watched updates
            content.categoryIdentifier = "WATCHED_CATEGORY"
        default:
            content.title = getNotificationTitle(for: notification)
            // Set default category
            content.categoryIdentifier = "DEFAULT_CATEGORY"
        }
        
        // Use message from notification or create a default one
        content.body = notification.message ?? "New notification from OpenProject"
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: self.unreadNotificationCount)
        
        // Add more context to the userInfo to enable better deep linking
        var userInfo: [String: Any] = ["notificationId": notification.id]
        
        if let resourceType = notification.resourceType, let resourceId = notification.resourceId {
            userInfo["resourceType"] = resourceType
            userInfo["resourceId"] = resourceId
        }
        
        content.userInfo = userInfo
        
        // Create a trigger (immediate delivery)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "notification-\(notification.id)-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        // Add request to notification center
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error creating local notification: \(error)")
            } else {
                print("Local notification created successfully for ID: \(notification.id)")
            }
        }
    }
    
    // Helper to find custom field by ID or name
    func getCustomField(id: Int? = nil, name: String? = nil) -> CustomField? {
        if let id = id {
            return customFields.first(where: { $0.id == id })
        } else if let name = name {
            return customFields.first(where: { $0.name.lowercased() == name.lowercased() })
        }
        return nil
    }
    
    // Find a custom field with ID 3 (customField3)
    var customField3: CustomField? {
        return getCustomField(id: 3)
    }
    
    // Fetch custom fields
    func fetchCustomFields() {
        guard let token = accessToken else { return }
        isLoadingCustomFields = true
        
        // Custom fields endpoint
        let url = URL(string: "\(apiBaseURL)/custom_fields")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("Fetching custom fields from: \(url.absoluteString)")
        
        URLSession.trustingSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingCustomFields = false
                
                if let error = error {
                    self.errorMessage = "Error fetching custom fields: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No custom fields data received"
                    return
                }
                
                // Print the response for debugging
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                }
                
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Data received: \(data.count) bytes")
                    print("Response preview: \(String(dataString.prefix(200)))...")
                }
                
                do {
                    let customFieldCollection = try JSONDecoder().decode(CustomFieldCollection.self, from: data)
                    self.customFields = customFieldCollection.elements
                    print("Custom fields parsed successfully: \(self.customFields.count)")
                    
                    // Fetch options for each list custom field
                    for customField in self.customFields {
                        if customField.fieldFormat == "list" && customField._links.options != nil {
                            self.fetchCustomOptions(for: customField)
                        }
                    }
                    
                } catch {
                    print("Error decoding custom fields: \(error)")
                    self.errorMessage = "Error parsing custom fields: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // Fetch custom options for a specific custom field
    private func fetchCustomOptions(for customField: CustomField) {
        guard let token = accessToken, let optionsLink = customField._links.options?.href else { return }
        
        // Construct full URL for options
        let optionsURL: URL
        if optionsLink.hasPrefix("http") {
            optionsURL = URL(string: optionsLink)!
        } else {
            let baseURLWithoutTrailingSlash = apiBaseURL.hasSuffix("/") 
                ? String(apiBaseURL.dropLast())
                : apiBaseURL
            
            let path = optionsLink.hasPrefix("/") ? optionsLink : "/\(optionsLink)"
            optionsURL = URL(string: "\(baseURLWithoutTrailingSlash)\(path)")!
        }
        
        var request = URLRequest(url: optionsURL)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("Fetching custom options for field \(customField.id) from: \(optionsURL.absoluteString)")
        
        URLSession.trustingSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching custom options: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No custom options data received")
                    return
                }
                
                do {
                    let optionsCollection = try JSONDecoder().decode(CustomOptionCollection.self, from: data)
                    
                    // Update the options for this custom field
                    if let index = self.customFields.firstIndex(where: { $0.id == customField.id }) {
                        self.customFields[index].customOptions = optionsCollection.elements
                        print("Loaded \(optionsCollection.elements.count) options for custom field \(customField.id)")
                    }
                } catch {
                    print("Error decoding custom options: \(error)")
                }
            }
        }.resume()
    }
    
    // Schedule a push notification for a notification that came from the server
    func scheduleLocalNotification(for notification: Notification) {
        let content = UNMutableNotificationContent()
        content.title = getNotificationTitle(for: notification)
        content.body = notification.message ?? "New notification"
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: unreadNotificationCount + 1)
        
        // Include notification ID and resource ID in the payload for deep linking
        var userInfo: [String: Any] = ["notificationId": notification.id]
        
        // Add resource information if available for deep linking
        if let resourceId = notification.resourceId {
            userInfo["resourceId"] = resourceId
            
            if let resourceType = notification.resourceType {
                userInfo["resourceType"] = resourceType
                
                // Add specific key for work packages for easier handling
                if resourceType == "WorkPackage" || resourceType == "work_packages" {
                    userInfo["workPackageId"] = resourceId
                } else if resourceType == "Project" || resourceType == "projects" {
                    userInfo["projectId"] = resourceId
                }
            }
        }
        
        content.userInfo = userInfo
        
        // Schedule immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "notification-\(notification.id)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Successfully scheduled notification for: \(notification.id)")
            }
        }
    }
    
    // Generate title based on notification type
    private func getNotificationTitle(for notification: Notification) -> String {
        // Default title if we can't generate a better one
        var title = "OpenProject Notification"
        
        // First try to generate title based on reason
        switch notification.reason {
        case "mentioned":
            title = "You were mentioned"
        case "assigned":
            title = "Assignment notification"
        case "responsible":
            title = "You are now responsible"
        case "watched":
            title = "Watched work package updated"
        case "commented":
            title = "New comment"
        default:
            // If no specific reason match, try to build a title from resource info
            if let resourceType = notification.resourceType, let resourceName = notification.resourceName {
                // Clean up the resource type (convert from API format to readable format)
                let cleanType = resourceType
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                
                // Create a more descriptive title
                title = "\(cleanType): \(resourceName)"
            }
        }
        
        return title
    }
    
    // Manually create a notification (for testing purposes)
    func createTestNotification(reason: String, message: String, resourceType: String, resourceName: String) {
        let id = Int.random(in: 1000...9999)
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        
        let defaultLink = Link(href: "", title: nil, templated: false, method: "GET")
        
        let notificationLinks = NotificationLinks(
            actor: defaultLink,
            project: nil,
            resource: defaultLink,
            activity: nil,
            readIAN: defaultLink,
            unreadIAN: defaultLink
        )
        
        let notification = Notification(
            id: id,
            reason: reason,
            readIAN: false,
            message: message,
            resourceType: resourceType,
            resourceId: id,
            resourceName: resourceName,
            createdAt: dateFormatter.string(from: currentDate),
            updatedAt: nil,
            links: notificationLinks
        )
        
        notifications.append(notification)
        unreadNotificationCount += 1
        
        // Schedule a local notification
        scheduleLocalNotification(for: notification)
    }
    
    // Process mention notifications from comments
    func processMention(mentionedUser: User, workPackage: WorkPackage) {
        if mentionedUser.id == user?.id {
            // Create a notification for being mentioned
            createTestNotification(
                reason: "mentioned",
                message: "You were mentioned in '\(workPackage.subject)'",
                resourceType: "WorkPackage",
                resourceName: workPackage.subject
            )
        }
    }
    
    // Process assignee notifications
    func processAssigneeChange(workPackage: WorkPackage, oldAssignee: User?, newAssignee: User?) {
        if newAssignee?.id == user?.id && oldAssignee?.id != user?.id {
            // Create a notification for being assigned
            createTestNotification(
                reason: "assigned",
                message: "You were assigned to '\(workPackage.subject)'",
                resourceType: "WorkPackage",
                resourceName: workPackage.subject
            )
        }
    }
    
    // Mark notification as read when received or viewed
    func markNotificationAsRead(id: Int) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else {
            print("Notification not found: \(id)")
            return
        }
        
        // First update local state
        if !notifications[index].readIAN {
            notifications[index].readIAN = true
            unreadNotificationCount = max(0, unreadNotificationCount - 1)
            
            // Then try to update on server if readIAN link is available
            if let readIANLink = notifications[index].links.readIAN?.href {
                markNotificationAsReadOnServer(readIANLink: readIANLink)
            }
        }
    }
    
    // Mark notification as read on the server
    private func markNotificationAsReadOnServer(readIANLink: String) {
        guard let accessToken = self.accessToken else { return }
        
        // Handle relative vs absolute URL
        let fullReadIANUrl: URL
        if readIANLink.hasPrefix("http") {
            guard let url = URL(string: readIANLink) else { return }
            fullReadIANUrl = url
        } else {
            let baseURL = apiBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
            let relativePath: String
            
            // Handle potential API version path duplication
            if readIANLink.hasPrefix("/api/v3/") && baseURL.contains("/api/v3") {
                let baseWithoutApiPath = baseURL.replacingOccurrences(of: "/api/v3", with: "")
                guard let url = URL(string: "\(baseWithoutApiPath)\(readIANLink)") else { return }
                fullReadIANUrl = url
                print("Creating URL without duplicating api/v3: \(fullReadIANUrl.absoluteString)")
            } else {
                relativePath = readIANLink.hasPrefix("/") ? readIANLink : "/\(readIANLink)"
                guard let url = URL(string: "\(baseURL)\(relativePath)") else { return }
                fullReadIANUrl = url
            }
        }
        
        var request = URLRequest(url: fullReadIANUrl)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error marking notification as read: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Mark as read response: \(httpResponse.statusCode)")
                if (200...299).contains(httpResponse.statusCode) {
                    print("Successfully marked notification as read on server")
                } else {
                    print("Failed to mark notification as read on server: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
    
    // Add a method to refresh the access token
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = self.refreshToken else {
            print("No refresh token available")
            completion(false)
            return
        }
        
        let tokenURL = "\(oauthBaseURL)/token"
        print("Refreshing token at: \(tokenURL)")
        
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let parameterString = parameters.map { key, value in
            return "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }.joined(separator: "&")
        
        request.httpBody = parameterString.data(using: .utf8)
        
        // Create a completely insecure session just for token refresh
        let insecureSessionConfig = URLSessionConfiguration.default
        
        // Create a one-time trust-all-certificates delegate
        class TokenRefreshDelegate: NSObject, URLSessionDelegate {
            override init() {
                super.init()
                print("TokenRefreshDelegate initialized")
            }
            
            func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                print("TokenRefresh: SSL Challenge received for \(challenge.protectionSpace.host)")
                // Accept ANY certificate unconditionally
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                print("TokenRefresh: SSL Task Challenge received for \(challenge.protectionSpace.host)")
                // Accept ANY certificate unconditionally
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
        }
        
        let insecureSession = URLSession(configuration: insecureSessionConfig, delegate: TokenRefreshDelegate(), delegateQueue: nil)
        
        print("Using insecure session for token refresh with URL: \(request.url?.absoluteString ?? "unknown")")
        insecureSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Token refresh error: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let response = response as? HTTPURLResponse else {
                    print("Token refresh error: No response received")
                    completion(false)
                    return
                }
                
                print("Token refresh response status: \(response.statusCode)")
                
                if response.statusCode != 200 {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Token refresh error response: \(responseString)")
                    }
                    // If we get a 401 or 403, the refresh token is invalid
                    if response.statusCode == 401 || response.statusCode == 403 {
                        self.logout()
                    }
                    completion(false)
                    return
                }
                
                guard let data = data else {
                    print("No data received from token refresh")
                    completion(false)
                    return
                }
                
                do {
                    let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                    
                    // Save new token information
                    self.accessToken = tokenResponse.accessToken
                    self.refreshToken = tokenResponse.refreshToken
                    
                    // Calculate new expiration date
                    let expirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                    self.tokenExpirationDate = expirationDate
                    
                    // Save updated token data to keychain
                    self.saveUserData()
                    
                    // Update UserCache with new token
                    UserCache.shared.setToken(tokenResponse.accessToken)
                    
                    print("Token successfully refreshed. Expires in: \(tokenResponse.expiresIn) seconds")
                    completion(true)
                } catch {
                    print("Failed to parse token refresh response: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }.resume()
    }
    
    // Register device token with the server for push notifications
    func registerDeviceToken(_ token: String) {
        guard let accessToken = self.accessToken else {
            print("Can't register device token - no access token")
            // Cache the token for later
            UserDefaults.standard.set(token, forKey: "pendingDeviceToken")
            return
        }
        
        // Only proceed if we have a user ID
        guard let userId = user?.id else {
            print("Can't register device token - no user ID")
            // Cache the token for later
            UserDefaults.standard.set(token, forKey: "pendingDeviceToken")
            return
        }
        
        print("Registering device token with server...")
        
        // Create device registration URL
        let urlString = "\(apiBaseURL)/device_registrations"
        guard let url = URL(string: urlString) else {
            print("Invalid device registration URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get device information
        let deviceName = UIDevice.current.name
        let deviceModel = UIDevice.current.model
        let systemName = UIDevice.current.systemName
        let systemVersion = UIDevice.current.systemVersion
        
        // Create registration payload with enhanced information
        let registrationData: [String: Any] = [
            "deviceToken": token,
            "deviceType": "ios",
            "deviceName": deviceName,
            "deviceModel": deviceModel,
            "systemName": systemName,
            "systemVersion": systemVersion,
            "userId": userId,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? ""
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: registrationData)
        } catch {
            print("Error serializing device registration data: \(error)")
            return
        }
        
        // Print the full request for debugging
        print("Device registration request: \(request.url?.absoluteString ?? "")")
        print("Device registration headers: \(request.allHTTPHeaderFields ?? [:])")
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("Device registration body: \(bodyString)")
        }
        
        URLSession.trustingSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error registering device token: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid HTTP response from device registration")
                return
            }
            
            print("Device registration status code: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                print("Device token registered successfully")
                
                // Save that we've registered this token
                UserDefaults.standard.set(token, forKey: "registeredDeviceToken")
                
                // Schedule a local test notification to verify notifications are working
                self.scheduleTestNotification()
            } else {
                print("Failed to register device token: HTTP \(httpResponse.statusCode)")
                
                // Log response for debugging
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }
            }
        }.resume()
    }
    
    // Schedule a test notification to verify push setup
    private func scheduleTestNotification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let content = UNMutableNotificationContent()
            content.title = "Notification Test"
            content.body = "This is a test notification to verify your notification setup is working"
            content.sound = UNNotificationSound.default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: "testNotification", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling test notification: \(error)")
                } else {
                    print("Test notification scheduled successfully")
                }
            }
        }
    }
    
    // Create local notifications for new unread app notifications
    private func createLocalNotificationsFor(notifications: [Notification]) {
        print("Creating local notifications for \(notifications.count) new notifications")
        
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = getNotificationTitle(for: notification)
            content.body = notification.message ?? "New notification"
            content.sound = UNNotificationSound.default
            
            // Set the badge count directly
            content.badge = NSNumber(value: unreadNotificationCount)
            
            // Enable foreground presentation
            content.categoryIdentifier = "FOREGROUND_VISIBLE"
            
            // Add notification ID and resource ID to the payload for deep linking
            var userInfo: [String: Any] = ["notificationId": notification.id]
            
            // Add resource information if available for deep linking
            if let resourceId = notification.resourceId {
                userInfo["resourceId"] = resourceId
                
                if let resourceType = notification.resourceType {
                    userInfo["resourceType"] = resourceType
                    
                    // Add specific key for work packages for easier handling
                    if resourceType.lowercased().contains("workpackage") || resourceType.lowercased().contains("work_package") {
                        userInfo["workPackageId"] = resourceId
                    } else if resourceType.lowercased().contains("project") {
                        userInfo["projectId"] = resourceId
                    }
                }
            }
            
            content.userInfo = userInfo
            
            // Create a unique identifier
            let requestIdentifier = "openproject-notification-\(notification.id)"
            
            // Schedule immediate delivery
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
            
            // Add the notification request
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    print("Local notification scheduled for notification ID: \(notification.id)")
                    
                    // Update badge immediately after scheduling notification
                    DispatchQueue.main.async {
                        UNUserNotificationCenter.current().setBadgeCount(self.unreadNotificationCount) { error in
                            if let error = error {
                                print("Error setting badge count: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Set up a timer to periodically check for notifications
    private func setupNotificationTimer() {
        // Create a timer that fires every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self, self.isLoggedIn else { return }
            
            print("Timer triggered: checking for new notifications")
            self.fetchNotifications()
        }
    }
    
    // Schedule a background notification check
    func scheduleBackgroundNotificationCheck() {
        // Cancel any existing timer
        notificationUpdateTimer?.invalidate()
        
        // Create new timer that checks for notifications every 30 seconds when the app is in the background
        notificationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkForNewNotificationsInBackground()
        }
        
        // Ensure timer continues to run in background
        RunLoop.current.add(notificationUpdateTimer!, forMode: .common)
        
        print("Scheduled background notification check every 30 seconds")
    }
    
    // Force an immediate check for new notifications
    func checkForNewNotifications() {
        fetchNotifications()
    }
    
    func checkForNewNotificationsInBackground() {
        // Start background task to ensure we have time to complete our fetch
        registerBackgroundTask()
        
        fetchNotifications { [weak self] success in
            guard let self = self else {
                self?.endBackgroundTask()
                return
            }
            
            // Update badge count in background
            UNUserNotificationCenter.current().setBadgeCount(self.unreadNotificationCount) { error in
                if let error = error {
                    print("Error setting badge count: \(error)")
                }
            }
            print("Setting badge count from background fetch: \(self.unreadNotificationCount)")
            
            // End background task
            self.endBackgroundTask()
        }
    }
    
    private func registerBackgroundTask() {
        self.backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if self.backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }
    
    private func setupTokenRefreshTimer() {
        // Check token every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isLoggedIn {
                self.refreshAccessToken { success in
                    if !success {
                        // If refresh fails, log out the user
                        self.logout()
                    }
                }
            }
        }
    }
} 
