//
//  MainTabView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Projects Tab
            NavigationView {
                ProjectsView()
            }
            .tabItem {
                Label("Projects", systemImage: "folder")
            }
            .tag(0)
            
            // Work Packages Tab
            NavigationView {
                WorkPackagesView(project: nil)
            }
            .tabItem {
                Label("Work Packages", systemImage: "list.bullet")
            }
            .tag(1)
            
            // Notifications Tab
            NotificationView()
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
            .badge(appState.unreadNotificationCount)
            .tag(2)
            .onChange(of: selectedTab) { oldTab, newTab in
                if newTab == 2 {
                    // Force notification refresh when switching to this tab
                    appState.fetchNotifications()
                }
            }
            
            // Profile/Settings Tab
            NavigationView {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(3)
        }
        .onAppear {
            // Refresh data when the view appears
            appState.fetchProjects()
            appState.fetchNotifications()
            
            // Schedule background notification check
            appState.scheduleBackgroundNotificationCheck()
            
            // Update app badge with the unread notification count
            let count = appState.unreadNotificationCount
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error = error {
                    print("Error setting badge count: \(error)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNotification"))) { _ in
            // Navigate to notifications tab
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWorkPackage"))) { notification in
            if let workPackageId = notification.object as? Int {
                // Navigate to work packages tab
                selectedTab = 1
                // Additional navigation will be handled in WorkPackagesView
                NotificationCenter.default.post(name: NSNotification.Name("NavigateToWorkPackage"), object: workPackageId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Check for new notifications when the app becomes active
            appState.checkForNewNotifications()
        }
        .onChange(of: appState.unreadNotificationCount) { oldCount, newCount in
            // Update badge when unread count changes
            UNUserNotificationCenter.current().setBadgeCount(newCount) { error in
                if let error = error {
                    print("Error setting badge count: \(error)")
                }
            }
        }
    }
}

struct ProjectSelectionView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack {
            Text("Please select a project first")
                .font(.headline)
                .padding()
            
            Button("Go to Projects") {
                // Switch to Projects tab using the binding
                selectedTab = 0
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .navigationTitle("Work Packages")
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AppState())
    }
}

// Add a preview for ProjectSelectionView
struct ProjectSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProjectSelectionView(selectedTab: .constant(0))
                .environmentObject(AppState())
        }
    }
} 