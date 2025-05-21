//
//  NotificationView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
import UserNotifications

// Import models directly

struct NotificationView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingFilter = false
    @State private var filterStatus: String = "All"
    @State private var navigateToWorkPackage: Int? = nil
    
    var filteredNotifications: [Notification] {
        switch filterStatus {
        case "Unread":
            return appState.notifications.filter { !$0.readIAN }
        case "Read":
            return appState.notifications.filter { $0.readIAN }
        default:
            return appState.notifications
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if appState.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding()
                } else if appState.notifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No notifications")
                            .font(.headline)
                        Text("You don't have any notifications yet")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredNotifications) { notification in
                            NotificationRow(notification: notification)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    print("Notification tapped: \(notification.id), type: \(notification.resourceType ?? "unknown")")
                                    // Handle notification tap with feedback
                                    handleNotificationTap(notification: notification)
                                }
                        }
                        .onDelete(perform: deleteNotification)
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        appState.fetchNotifications { success in
                            print("Notifications refreshed, success: \(success)")
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarItems(trailing: 
                Menu {
                    Button("All") { filterStatus = "All" }
                    Button("Unread") { filterStatus = "Unread" }
                    Button("Read") { filterStatus = "Read" }
                    
                    Divider()
                    
                    Button("Mark all as read") {
                        markAllAsRead()
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            )
            .background(
                NavigationLink(
                    destination: WorkPackageDetailView(workPackageId: navigateToWorkPackage ?? 0)
                        .environmentObject(appState),
                    isActive: Binding(
                        get: { navigateToWorkPackage != nil },
                        set: { if !$0 { navigateToWorkPackage = nil } }
                    )
                ) {
                    EmptyView()
                }
            )
        }
        .onAppear {
            appState.fetchNotifications { success in
                print("Notifications loaded on appear, success: \(success)")
            }
            
            // Setup observer for navigation notifications
            NotificationCenter.default.addObserver(
                forName: Foundation.Notification.Name("NavigateToWorkPackage"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let workPackageId = userInfo["workPackageId"] as? Int {
                    self.navigateToWorkPackage = workPackageId
                }
            }
        }
        .onDisappear {
            // Remove the observer when the view disappears
            NotificationCenter.default.removeObserver(
                self,
                name: Foundation.Notification.Name("NavigateToWorkPackage"),
                object: nil
            )
        }
        // Use the single-parameter version of onChange for iOS 15 compatibility
        .onChange(of: appState.navigateTo) { newValue in
            if let newValue = newValue, case let .workPackage(id) = newValue.destination {
                self.navigateToWorkPackage = id
                // Reset the navigation state after handling it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.appState.navigateTo = nil
                }
            }
        }
    }
    
    private func markNotificationAsRead(notification: Notification) {
        guard let accessToken = appState.accessToken else { return }
        guard appState.notifications.firstIndex(where: { $0.id == notification.id }) != nil else {
            print("Notification not found in state")
            return
        }
        
        // First, try to navigate to the resource if available
        navigateToResource(notification: notification)
        
        // Then, try to mark as read if the link is available
        guard let readIANLink = notification.links.readIAN?.href else {
            print("No readIAN link available")
            // Even if there's no readIAN link, we'll update local state to appear read
            updateLocalNotificationReadState(notification: notification)
            return
        }
        
        // Fix: Ensure we have a complete URL by adding base URL if needed
        let fullReadIANUrl: URL
        if readIANLink.hasPrefix("http") {
            // It's already a full URL
            guard let url = URL(string: readIANLink) else {
                print("Invalid readIAN URL: \(readIANLink)")
                updateLocalNotificationReadState(notification: notification)
                return
            }
            fullReadIANUrl = url
        } else {
            // It's a relative URL, prepend the API base URL
            let baseURL = appState.apiBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
            
            // Check if the readIANLink already includes "api/v3" to avoid duplication
            let relativePath: String
            if readIANLink.hasPrefix("/api/v3/") {
                // Already has API version path, so we need to remove it from the base URL if present
                if baseURL.hasSuffix("/api/v3") || baseURL.contains("/api/v3/") {
                    // Remove the api/v3 from base URL
                    let baseWithoutApiPath = baseURL.replacingOccurrences(of: "/api/v3", with: "")
                    let fullUrl = "\(baseWithoutApiPath)\(readIANLink)"
                    print("Modified URL construction to avoid duplication: \(fullUrl)")
                    guard let url = URL(string: fullUrl) else {
                        print("Failed to create full URL with modified base: \(baseWithoutApiPath) and relative: \(readIANLink)")
                        updateLocalNotificationReadState(notification: notification)
                        return
                    }
                    fullReadIANUrl = url
                    print("Final URL: \(fullReadIANUrl.absoluteString)")
                    var request = URLRequest(url: fullReadIANUrl)
                    request.httpMethod = "POST"
                    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        self.mainThreadSafe {
                            if let error = error {
                                print("Error marking notification as read: \(error)")
                                self.appState.errorMessage = "Failed to mark notification as read"
                                return
                            }
                            
                            if let httpResponse = response as? HTTPURLResponse {
                                print("Mark as read response code: \(httpResponse.statusCode)")
                                if (200...299).contains(httpResponse.statusCode) {
                                    self.updateLocalNotificationReadState(notification: notification)
                                    print("Notification marked as read")
                                } else {
                                    print("Failed to mark notification as read: HTTP \(httpResponse.statusCode)")
                                    self.appState.errorMessage = "Failed to mark notification as read"
                                }
                            }
                        }
                    }.resume()
                    return
                } else {
                    // Base URL doesn't have api/v3, so we use the readIANLink as is
                    relativePath = readIANLink
                }
            } else if baseURL.hasSuffix("/api/v3") || baseURL.hasSuffix("/api/v3/") {
                // Base URL already has API version path, don't add it again
                let cleanRelativePath = readIANLink.hasPrefix("/") ? String(readIANLink.dropFirst()) : readIANLink
                relativePath = "/\(cleanRelativePath)"
            } else {
                // Both are missing API version, need to decide which is correct
                relativePath = readIANLink.hasPrefix("/") ? readIANLink : "/\(readIANLink)"
            }
            
            print("Constructing URL from: base='\(baseURL)', relative='\(relativePath)'")
            
            guard let url = URL(string: "\(baseURL)\(relativePath)") else {
                print("Failed to create full URL from base: \(baseURL) and relative: \(relativePath)")
                updateLocalNotificationReadState(notification: notification)
                return
            }
            fullReadIANUrl = url
        }
        
        print("Marking notification as read: \(fullReadIANUrl.absoluteString)")
        
        var request = URLRequest(url: fullReadIANUrl)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.mainThreadSafe {
                if let error = error {
                    print("Error marking notification as read: \(error)")
                    self.appState.errorMessage = "Failed to mark notification as read"
                    return
                }
                
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    self.updateLocalNotificationReadState(notification: notification)
                }
            }
        }.resume()
    }
    
    // Helper method to ensure code runs on the main thread
    private func mainThreadSafe(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    // New helper function to update local state
    private func updateLocalNotificationReadState(notification: Notification) {
        // Update local state
        var updatedNotifications = self.appState.notifications
        if let index = updatedNotifications.firstIndex(where: { $0.id == notification.id }) {
            updatedNotifications[index].readIAN = true
        }
        
        self.appState.notifications = updatedNotifications
        
        // Only decrease count if it was previously unread
        if !notification.readIAN {
            self.appState.unreadNotificationCount = max(0, self.appState.unreadNotificationCount - 1)
            
            // Update application badge
            UIApplication.shared.applicationIconBadgeNumber = Int(self.appState.unreadNotificationCount)
            
            // Use setBadgeCount on iOS 16+ only
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(Int(self.appState.unreadNotificationCount)) { error in
                    if let error = error {
                        print("Error setting badge count: \(error)")
                    }
                }
            }
        }
    }
    
    // Update navigateToResource function to use app-specific navigation
    private func navigateToResource(notification: Notification) {
        print("Navigating to resource for notification: \(notification.debugDescription)")
        print("Notification links: \(notification.links.debugDescription)")
        
        // Try to get resource info from the notification fields first
        var resourceType = notification.resourceType
        var resourceId: Int? = notification.resourceId
        let resourceLink = notification.links.resource?.href
        
        // Extract project ID from links if available
        var projectId: Int? = nil
        if let projectLink = notification.links.project?.href {
            projectId = extractProjectIdFromLink(projectLink)
            print("Extracted project ID \(projectId ?? 0) from project link")
        }
        
        // If resource type is nil but we have a resource link, try to extract info from the link
        if (resourceType == nil || resourceId == nil) && resourceLink != nil {
            // Extract resource type and ID from resource link
            let extractedInfo = extractResourceInfoFromLink(resourceLink!)
            if resourceType == nil {
                resourceType = extractedInfo.type
            }
            if resourceId == nil {
                resourceId = extractedInfo.id
            }
        }
        
        guard let finalResourceType = resourceType,
              let finalResourceId = resourceId else {
            print("Cannot navigate: missing resource information")
            return
        }
        
        let finalResourceLink = resourceLink ?? ""
        print("Attempting to navigate to \(finalResourceType) with ID \(finalResourceId), href: \(finalResourceLink)")
        
        switch finalResourceType {
        case "WorkPackage", "work_packages":
            // Find work package in current project if available
            let workPackageId = finalResourceId
            
            // If we already have a project ID from the notification links, use that
            if let projId = projectId {
                setCurrentProjectAndNavigateToWorkPackage(projectId: projId, workPackageId: workPackageId)
                return
            }
            
            // If we have a current project selected, check if it matches
            if let currentProject = appState.currentProject {
                print("Looking for work package \(workPackageId) in project \(currentProject.name)")
                
                // If we have a resource link, check if it contains the current project ID
                if !finalResourceLink.isEmpty {
                    if let projIdFromWP = extractProjectIdFromWorkPackageHref(href: finalResourceLink) {
                        if projIdFromWP == currentProject.id {
                            // The work package is in the current project, navigate directly
                            navigateToWorkPackage(workPackageId: workPackageId)
                            return
                        } else {
                            // The work package is in a different project, switch projects
                            setCurrentProjectAndNavigateToWorkPackage(projectId: projIdFromWP, workPackageId: workPackageId)
                            return
                        }
                    }
                }
                
                // Default to current project if we couldn't extract project info
                navigateToWorkPackage(workPackageId: workPackageId)
            } else {
                // No current project, extract project ID from the resource href
                print("No current project selected, extracting project for work package \(workPackageId)")
                
                if let projIdFromWP = extractProjectIdFromWorkPackageHref(href: finalResourceLink) {
                    setCurrentProjectAndNavigateToWorkPackage(projectId: projIdFromWP, workPackageId: workPackageId)
                } else {
                    print("Could not determine project for work package \(workPackageId)")
                    // If we can't determine the project, attempt to fetch the work package
                    // to get its project information (implementation depends on your API)
                    fetchWorkPackageToNavigate(workPackageId: workPackageId)
                }
            }
            
        case "Project":
            // Navigate to project detail
            let projectId = finalResourceId
            setCurrentProject(projectId: projectId)
            
        case "Comment":
            // Extract work package ID from comment link if possible
            if let wpId = extractWorkPackageIdFromCommentHref(href: finalResourceLink) {
                print("Comment is on work package \(wpId)")
                
                // Try to extract project ID as well
                if let projId = extractProjectIdFromCommentHref(href: finalResourceLink) {
                    setCurrentProjectAndNavigateToWorkPackage(projectId: projId, workPackageId: wpId)
                } else {
                    // If no project ID in the comment link, try using current project
                    if let currentProject = appState.currentProject {
                        navigateToWorkPackage(workPackageId: wpId)
                    } else {
                        // No current project, fetch work package to determine project
                        fetchWorkPackageToNavigate(workPackageId: wpId)
                    }
                }
            } else {
                print("Could not extract work package ID from comment link: \(finalResourceLink)")
            }
            
        case "Activity":
            // Similar to comments, activities are usually related to work packages
            if let wpId = extractWorkPackageIdFromActivityHref(href: finalResourceLink) {
                print("Activity is on work package \(wpId)")
                
                if let projId = extractProjectIdFromActivityHref(href: finalResourceLink) {
                    setCurrentProjectAndNavigateToWorkPackage(projectId: projId, workPackageId: wpId)
                } else if appState.currentProject != nil {
                    navigateToWorkPackage(workPackageId: wpId)
                } else {
                    fetchWorkPackageToNavigate(workPackageId: wpId)
                }
            } else {
                print("Could not extract work package ID from activity link: \(finalResourceLink)")
            }
            
        default:
            print("Navigation not implemented for resource type: \(finalResourceType)")
        }
    }
    
    // Helper methods for navigation
    
    private func setCurrentProject(projectId: Int) {
        print("Setting current project to ID: \(projectId)")
        if let project = appState.projects.first(where: { $0.id == projectId }) {
            print("Found project: \(project.name)")
            appState.currentProject = project
            // Any additional navigation you need to do for projects
        } else {
            print("Project with ID \(projectId) not found in loaded projects")
            // Optionally fetch the project if not in the current list
        }
    }
    
    private func navigateToWorkPackage(workPackageId: Int) {
        guard let currentProject = appState.currentProject else {
            print("No current project selected, cannot navigate to work package")
            return
        }
        
        print("Navigating to work package \(workPackageId) in project \(currentProject.name)")
        
        // Store the selected work package ID in app state
        appState.selectedWorkPackageId = workPackageId
        
        // Use a combination of NotificationCenter post (for views that are already loaded)
        // and direct app state updates (for views being initialized)
        NotificationCenter.default.post(
            name: Foundation.Notification.Name("NavigateToWorkPackage"),
            object: nil,
            userInfo: ["workPackageId": workPackageId, "projectId": currentProject.id]
        )
        
        // Set a flag to trigger navigation in other views
        appState.navigateTo = NavigationDestination(destination: .workPackage(id: workPackageId))
    }
    
    private func setCurrentProjectAndNavigateToWorkPackage(projectId: Int, workPackageId: Int) {
        setCurrentProject(projectId: projectId)
        navigateToWorkPackage(workPackageId: workPackageId)
    }
    
    private func fetchWorkPackageToNavigate(workPackageId: Int) {
        print("Would fetch work package \(workPackageId) to determine its project")
        // Implement actual API call to fetch work package details
        // Then set current project and navigate to work package
    }
    
    // Extract project ID from various link types
    
    private func extractProjectIdFromLink(_ link: String) -> Int? {
        let components = link.split(separator: "/")
        for (index, component) in components.enumerated() {
            if component == "projects" && index + 1 < components.count,
               let projectId = Int(components[index + 1]) {
                return projectId
            }
        }
        return nil
    }
    
    private func extractWorkPackageIdFromCommentHref(href: String) -> Int? {
        // Implementation depends on your API structure
        // Example: /api/v3/work_packages/123/comments/456
        let components = href.split(separator: "/")
        for (index, component) in components.enumerated() {
            if component == "work_packages" && index + 1 < components.count,
               let wpId = Int(components[index + 1]) {
                return wpId
            }
        }
        return nil
    }
    
    private func extractProjectIdFromCommentHref(href: String) -> Int? {
        // Similar to extractProjectIdFromWorkPackageHref
        return extractProjectIdFromLink(href)
    }
    
    private func extractWorkPackageIdFromActivityHref(href: String) -> Int? {
        // Similar logic to comment links
        let components = href.split(separator: "/")
        for (index, component) in components.enumerated() {
            if component == "work_packages" && index + 1 < components.count,
               let wpId = Int(components[index + 1]) {
                return wpId
            }
        }
        return nil
    }
    
    private func extractProjectIdFromActivityHref(href: String) -> Int? {
        return extractProjectIdFromLink(href)
    }
    
    // Helper function to extract resource type and ID from a resource link
    private func extractResourceInfoFromLink(_ link: String) -> (type: String, id: Int?) {
        // Example resource link formats:
        // - /api/v3/work_packages/39
        // - /api/v3/projects/3
        // - /api/v3/comments/456
        
        let components = link.split(separator: "/")
        
        // Try to get the resource type and ID
        for (index, component) in components.enumerated() {
            if ["work_packages", "projects", "comments", "activities"].contains(component) && index + 1 < components.count {
                if let resourceId = Int(components[index + 1]) {
                    // Convert API path to resource type
                    let resourceType: String
                    switch component {
                    case "work_packages":
                        resourceType = "WorkPackage"
                    case "projects":
                        resourceType = "Project"
                    case "comments":
                        resourceType = "Comment"
                    case "activities":
                        resourceType = "Activity"
                    default:
                        resourceType = String(component)
                    }
                    return (resourceType, resourceId)
                }
            }
        }
        
        // Default values if extraction fails
        return ("Unknown", nil)
    }
    
    // Helper function to extract project ID from work package href
    private func extractProjectIdFromWorkPackageHref(href: String) -> Int? {
        // Example resource href format: /api/v3/projects/5/work_packages/123
        let components = href.split(separator: "/")
        for (index, component) in components.enumerated() {
            if component == "projects" && index + 1 < components.count,
               let projectId = Int(components[index + 1]) {
                return projectId
            }
        }
        return nil
    }
    
    private func markAllAsRead() {
        guard let token = appState.accessToken else {
            return
        }
        
        let url = URL(string: "\(appState.apiBaseURL)/notifications/read_ian")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.mainThreadSafe {
                if let error = error {
                    print("Error marking all notifications as read: \(error)")
                    self.appState.errorMessage = "Failed to mark all notifications as read"
                    return
                }
                
                // Instead of directly modifying the readIAN property, 
                // fetch updated notifications from the server
                self.appState.fetchNotifications()
                self.appState.unreadNotificationCount = 0
                
                // Update app badge to zero
                UIApplication.shared.applicationIconBadgeNumber = 0
                
                // Use setBadgeCount on iOS 16+ only
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(0) { error in
                        if let error = error {
                            print("Error setting badge count to zero: \(error)")
                        }
                    }
                }
            }
        }.resume()
    }
    
    private func deleteNotification(at offsets: IndexSet) {
        // First collect the notifications that will be deleted
        var notificationsToDelete: [Notification] = []
        var unreadCountToDecrease = 0
        
        for index in offsets {
            let notification = filteredNotifications[index]
            notificationsToDelete.append(notification)
            
            // Count unread notifications that will be deleted
            if !notification.readIAN {
                unreadCountToDecrease += 1
            }
        }
        
        // Try to delete notifications from the server if API supports it
        for notification in notificationsToDelete {
            // Remove from local state
            if let actualIndex = appState.notifications.firstIndex(where: { $0.id == notification.id }) {
                appState.notifications.remove(at: actualIndex)
            }
            
            // Optional: Try to delete from server if API supports it
            deleteNotificationFromServer(notification)
        }
        
        // Update unread count
        if unreadCountToDecrease > 0 {
            appState.unreadNotificationCount = max(0, appState.unreadNotificationCount - unreadCountToDecrease)
            
            // Update application badge
            UIApplication.shared.applicationIconBadgeNumber = Int(appState.unreadNotificationCount)
            
            // Use setBadgeCount on iOS 16+ only
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(Int(appState.unreadNotificationCount)) { error in
                    if let error = error {
                        print("Error setting badge count: \(error)")
                    }
                }
            }
        }
    }
    
    private func deleteNotificationFromServer(_ notification: Notification) {
        guard let accessToken = appState.accessToken else { return }
        
        // Check if there's a direct URL for deleting the notification
        // Note: OpenProject API may not support notification deletion
        let urlString = "\(appState.apiBaseURL)/notifications/\(notification.id)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.mainThreadSafe {
                if let error = error {
                    print("Error deleting notification: \(error)")
                    self.appState.errorMessage = "Failed to delete notification"
                    return
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    print("Successfully deleted notification from server")
                } else {
                    print("Failed to delete notification from server")
                }
            }
        }.resume()
    }
    
    // Helper method to extract work package ID from a path
    private func extractWorkPackageIdFromPath(_ path: String) -> Int? {
        let components = path.split(separator: "/")
        for (index, component) in components.enumerated() {
            if component == "work_packages" && index + 1 < components.count,
               let workPackageId = Int(components[index + 1]) {
                return workPackageId
            }
        }
        return nil
    }
    
    // Add this new method to handle notification taps with better feedback
    private func handleNotificationTap(notification: Notification) {
        // First mark as read to update UI
        markNotificationAsRead(notification: notification)
        
        // Provide better feedback based on resource type
        if let resourceType = notification.resourceType, let resourceId = notification.resourceId {
            switch resourceType.lowercased() {
            case "workpackage", "work_package", "work_packages":
                // A loading indicator might be nice here
                print("Navigating to work package: \(resourceId)")
                
                // Set the navigation target
                self.navigateToWorkPackage = resourceId
                
            case "project":
                print("Navigating to project: \(resourceId)")
                // Your existing project navigation logic
                if let project = appState.projects.first(where: { $0.id == resourceId }) {
                    appState.currentProject = project
                    // Any navigation to project detail would go here
                } else {
                    // Maybe refresh projects list
                    appState.fetchProjects()
                }
                
            case "comment", "activity":
                if let wpId = extractRelatedWorkPackageId(notification: notification) {
                    print("Navigating to work package with comment/activity: \(wpId)")
                    self.navigateToWorkPackage = wpId
                }
                
            default:
                print("Unsupported resource type for navigation: \(resourceType)")
                // Still mark as read even if we can't navigate
            }
        } else {
            // Handle case where we don't have clear resource information
            print("No specific resource to navigate to")
            
            // Try to use links for navigation if resource type/id is missing
            navigateToResource(notification: notification)
        }
    }
    
    // Helper method to extract work package ID from a comment or activity notification
    private func extractRelatedWorkPackageId(notification: Notification) -> Int? {
        // Check if we have a direct resource ID
        if let resourceType = notification.resourceType?.lowercased(),
           resourceType == "workpackage" || resourceType == "work_package" || resourceType == "work_packages",
           let resourceId = notification.resourceId {
            return resourceId
        }
        
        // Try to extract from resource link
        if let resourceLink = notification.links.resource?.href {
            if resourceLink.contains("work_packages") {
                // Extract ID from link like "/api/v3/work_packages/123"
                let components = resourceLink.split(separator: "/")
                if let lastComponent = components.last, let id = Int(lastComponent) {
                    return id
                }
            }
        }
        
        // Try to extract from resource activity link
        if let activityLink = notification.links.activity?.href {
            if activityLink.contains("work_packages") {
                // Extract ID from activity link
                let regex = try? NSRegularExpression(pattern: "/work_packages/(\\d+)/")
                if let regex = regex,
                   let match = regex.firstMatch(in: activityLink, range: NSRange(activityLink.startIndex..., in: activityLink)) {
                    if let range = Range(match.range(at: 1), in: activityLink) {
                        return Int(activityLink[range])
                    }
                }
            }
        }
        
        // Try to extract from message text as last resort
        if let message = notification.message {
            // Look for patterns like "Work Package #123" or similar
            let regex = try? NSRegularExpression(pattern: "#(\\d+)")
            if let regex = regex,
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
                if let range = Range(match.range(at: 1), in: message) {
                    return Int(message[range])
                }
            }
        }
        
        return nil
    }
}

struct NotificationRow: View {
    var notification: Notification
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Show unread indicator
                if !notification.readIAN {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                
                // Notification type with icon
                HStack(spacing: 4) {
                    Image(systemName: iconForNotificationType(notification.reason))
                        .foregroundColor(.blue)
                    
                    Text(formattedReason(notification.reason))
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(formatDate(notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Message with details about the notification
            if let message = notification.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            // Show combined actor and resource information
            HStack {
                if let actorName = notification.links.actor.title {
                    Text("By: \(actorName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let projectName = notification.links.project?.title {
                    Text("In: \(projectName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let resourceName = notification.resourceName {
                Text(resourceName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        // Make unread notifications stand out more
        .background(notification.readIAN ? Color.clear : Color.blue.opacity(0.05))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
    
    // Get appropriate icon for notification type
    private func iconForNotificationType(_ reason: String) -> String {
        switch reason.lowercased() {
        case "mentioned":
            return "person.crop.circle.badge.exclamationmark"
        case "assigned":
            return "person.badge.clock"
        case "responsible":
            return "person.badge.shield.checkmark"
        case "watched":
            return "eye"
        case "commented":
            return "text.bubble"
        case "created":
            return "plus.circle"
        case "updated":
            return "pencil.circle"
        case "status":
            return "arrow.triangle.2.circlepath"
        case "prioritized":
            return "exclamationmark.triangle"
        case "scheduled":
            return "calendar"
        default:
            return "bell"
        }
    }
    
    // Format notification reason to be more readable
    private func formattedReason(_ reason: String) -> String {
        switch reason.lowercased() {
        case "mentioned":
            return "Mentioned"
        case "assigned":
            return "Assigned"
        case "responsible":
            return "Responsible"
        case "watched":
            return "Updated"
        case "commented":
            return "New Comment"
        case "created":
            return "Created"
        case "updated":
            return "Updated"
        case "status":
            return "Status Changed"
        case "prioritized":
            return "Priority Changed"
        case "scheduled":
            return "Scheduled"
        default:
            return reason.capitalized
        }
    }
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString,
              !dateString.isEmpty else {
            return "Unknown date"
        }
        
        // Create a formatter that can handle ISO8601 strings
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try to parse the date with milliseconds first
        if let date = formatter.date(from: dateString) {
            return getRelativeTimeFormatted(date)
        }
        
        // Try without fractional seconds if the first attempt failed
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return getRelativeTimeFormatted(date)
        }
        
        // Fallback date formatter for other ISO formats
        let backupFormatter = DateFormatter()
        backupFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = backupFormatter.date(from: dateString) {
            return getRelativeTimeFormatted(date)
        }
        
        backupFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = backupFormatter.date(from: dateString) {
            return getRelativeTimeFormatted(date)
        }
        
        // As a last resort, just return the raw string
        return dateString
    }
    
    private func getRelativeTimeFormatted(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            if day == 1 {
                return "Yesterday"
            } else if day < 7 {
                return "\(day) days ago"
            } else {
                // For older dates, show the actual date
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter.string(from: date)
            }
        } else if let hour = components.hour, hour > 0 {
            return "\(hour) hour\(hour == 1 ? "" : "s") ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute) minute\(minute == 1 ? "" : "s") ago"
        } else {
            return "Just now"
        }
    }
}

struct NotificationView_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()
        
        // Add sample notifications for preview
        appState.notifications = [
            // Use constructor with all required fields
            Notification(
                id: 1,
                reason: "updated",
                readIAN: false,
                message: "Work package 'Fix login issue' was updated",
                resourceType: "WorkPackage",
                resourceId: 123,
                resourceName: "Fix login issue",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                links: NotificationLinks(
                    actor: Link(href: "/api/v3/users/1", title: "John Doe", templated: false, method: "GET"),
                    project: Link(href: "/api/v3/projects/1", title: "Sample Project", templated: false, method: "GET"),
                    resource: Link(href: "/api/v3/work_packages/123", title: "Work Package", templated: false, method: "GET"),
                    activity: nil,
                    readIAN: Link(href: "/api/v3/notifications/1/read_ian", title: "Mark as read", templated: false, method: "POST"),
                    unreadIAN: Link(href: "/api/v3/notifications/1/unread_ian", title: "Mark as unread", templated: false, method: "POST")
                )
            ),
            Notification(
                id: 2,
                reason: "mentioned",
                readIAN: true,
                message: "You were mentioned in 'Project kickoff meeting'",
                resourceType: "Comment",
                resourceId: 456,
                resourceName: "Project kickoff meeting",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400)),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                links: NotificationLinks(
                    actor: Link(href: "/api/v3/users/2", title: "Jane Smith", templated: false, method: "GET"),
                    project: Link(href: "/api/v3/projects/1", title: "Sample Project", templated: false, method: "GET"),
                    resource: Link(href: "/api/v3/comments/456", title: "Comment", templated: false, method: "GET"),
                    activity: nil,
                    readIAN: Link(href: "/api/v3/notifications/2/read_ian", title: "Mark as read", templated: false, method: "POST"),
                    unreadIAN: Link(href: "/api/v3/notifications/2/unread_ian", title: "Mark as unread", templated: false, method: "POST")
                )
            )
        ]
        
        return NotificationView()
            .environmentObject(appState)
    }
} 