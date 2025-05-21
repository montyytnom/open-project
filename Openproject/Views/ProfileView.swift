//
//  ProfileView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
import UserNotifications


struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingLogoutConfirmation = false
    @State private var showingAPISettings = false
    @State private var apiBaseURL = ""
    @State private var oauthBaseURL = ""
    
    var body: some View {
        Form {
            Section(header: Text("User Information")) {
                if let user = appState.user {
                    ProfileInfoRow(icon: "person.fill", title: "Name", value: "\(user.firstName) \(user.lastName)")
                    ProfileInfoRow(icon: "envelope.fill", title: "Email", value: user.email ?? "Not provided")
                    ProfileInfoRow(icon: "calendar", title: "Member Since", value: formattedDate(user.createdAt))
                } else {
                    Text("User information not available")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("App Settings")) {
                Button(action: {
                    showingAPISettings = true
                }) {
                    HStack {
                        Image(systemName: "link")
                            .frame(width: 25, height: 25)
                            .foregroundColor(.blue)
                        Text("API Connection")
                        Spacer()
                        Text(appState.apiBaseURL.components(separatedBy: "://").last ?? "")
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                    }
                }
                
                Toggle(isOn: .constant(true)) {
                    HStack {
                        Image(systemName: "bell.fill")
                            .frame(width: 25, height: 25)
                            .foregroundColor(.blue)
                        Text("Push Notifications")
                    }
                }
                
                Button(action: {
                    testNotifications()
                }) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .frame(width: 25, height: 25)
                            .foregroundColor(.blue)
                        Text("Test Notifications")
                    }
                }
                
                NavigationLink(destination: AboutView()) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .frame(width: 25, height: 25)
                            .foregroundColor(.blue)
                        Text("About")
                    }
                }
            }
            
            Section {
                Button(action: {
                    showingLogoutConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text("Log Out")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $showingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                appState.logout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAPISettings) {
            APISettingsView(
                apiBaseURL: $apiBaseURL,
                oauthBaseURL: $oauthBaseURL,
                isPresented: $showingAPISettings
            )
            .onAppear {
                apiBaseURL = appState.apiBaseURL
                oauthBaseURL = appState.oauthBaseURL
            }
        }
    }
    
    private func formattedDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return "Unknown"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func testNotifications() {
        // Test different types of notifications
        appState.createTestNotification(
            reason: "mentioned",
            message: "You were mentioned in 'Project kickoff meeting'",
            resourceType: "Comment",
            resourceName: "Project kickoff meeting"
        )
        
        appState.createTestNotification(
            reason: "assigned",
            message: "You were assigned to 'Implement new feature'",
            resourceType: "WorkPackage",
            resourceName: "Implement new feature"
        )
        
        // Schedule a local notification for a reminder test
        let content = UNMutableNotificationContent()
        content.title = "Test Reminder"
        content.body = "This is a test reminder notification"
        content.sound = UNNotificationSound.default
        
        // Set the badge count for testing
        content.badge = 1
        
        // Deliver after 5 seconds for testing
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-reminder-\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling test notification: \(error.localizedDescription)")
            }
        }
    }
}

struct ProfileInfoRow: View {
    var icon: String
    var title: String
    var value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 25, height: 25)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }
}

struct APISettingsView: View {
    @Binding var apiBaseURL: String
    @Binding var oauthBaseURL: String
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @State private var showingSaveAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Settings")) {
                    TextField("API Base URL", text: $apiBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("OAuth Base URL", text: $oauthBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(footer: Text("Changing these settings will require you to log in again.")) {
                    Button("Save Changes") {
                        appState.apiBaseURL = apiBaseURL
                        appState.oauthBaseURL = oauthBaseURL
                        showingSaveAlert = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("API Connection")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .alert(isPresented: $showingSaveAlert) {
                Alert(
                    title: Text("Settings Updated"),
                    message: Text("API connection settings have been updated. You'll need to log in again for these changes to take effect."),
                    primaryButton: .default(Text("Log Out Now")) {
                        isPresented = false
                        appState.logout()
                    },
                    secondaryButton: .cancel(Text("Later")) {
                        isPresented = false
                    }
                )
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section(header: Text("App Information")) {
                ProfileInfoRow(icon: "app.badge.fill", title: "App Name", value: "OpenProject Mobile")
                ProfileInfoRow(icon: "number", title: "Version", value: "1.0.0")
                ProfileInfoRow(icon: "checkmark.seal.fill", title: "OpenProject API", value: "v1.2.3")
            }
            
            Section(header: Text("Legal")) {
                NavigationLink(destination: TextContentView(title: "Terms of Service", content: "Terms of service text goes here...")) {
                    Text("Terms of Service")
                }
                
                NavigationLink(destination: TextContentView(title: "Privacy Policy", content: "Privacy policy text goes here...")) {
                    Text("Privacy Policy")
                }
                
                NavigationLink(destination: TextContentView(title: "Licenses", content: "Third-party licenses and attributions...")) {
                    Text("Licenses")
                }
            }
            
            Section {
                SwiftUI.Link(destination: URL(string: "https://www.openproject.org")!) {
                    HStack {
                        Text("Visit OpenProject Website")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                
                SwiftUI.Link(destination: URL(string: "https://www.openproject.org/docs/api")!) {
                    HStack {
                        Text("API Documentation")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("About")
    }
}

struct TextContentView: View {
    var title: String
    var content: String
    
    var body: some View {
        ScrollView {
            Text(content)
                .padding()
        }
        .navigationTitle(title)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileView()
                .environmentObject(createPreviewAppState())
        }
    }
    
    static func createPreviewAppState() -> AppState {
        let appState = AppState()
        appState.user = User(
            id: 1,
            name: "johndoe",
            firstName: "John",
            lastName: "Doe",
            email: "john.doe@example.com",
            avatar: nil,
            status: "active",
            language: "en",
            admin: false,
            createdAt: "2023-01-15T10:00:00Z",
            updatedAt: "2023-06-20T14:30:00Z"
        )
        return appState
    }
} 