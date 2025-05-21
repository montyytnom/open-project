//
//  ContentView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI

// Import models directly

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCheckingAuthentication = true
    
    var body: some View {
        ZStack {
            if isCheckingAuthentication {
                // Show loading indicator while checking token
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Checking authentication...")
                        .padding(.top, 16)
                }
            } else if appState.isLoggedIn {
                // User is logged in
                MainTabView()
            } else {
                // User needs to log in
                LoginView()
            }
        }
        .onAppear {
            // Check token validity on app launch
            validateTokenAndAuthentication()
        }
    }
    
    private func validateTokenAndAuthentication() {
        // First check if we have cached login state
        if UserDefaults.standard.bool(forKey: "isLoggedIn") {
            // We might be logged in, check if token exists and is valid
            if let token = appState.accessToken, 
               let expirationDate = appState.tokenExpirationDate {
                if expirationDate > Date() {
                    // Token is still valid, just confirm login state
                    isCheckingAuthentication = false
                    // Ensure we're marked as logged in
                    appState.isLoggedIn = true
                } else {
                    // Token exists but is expired, try to refresh it
                    appState.refreshAccessToken { success in
                        if success {
                            // Token refreshed, user is still logged in
                            print("Token refreshed successfully on app start")
                            // Ensure login state is set
                            appState.isLoggedIn = true
                            // Preload data after successful refresh
                            appState.fetchProjects()
                            appState.fetchNotifications { _ in }
                        } else {
                            // Failed to refresh, user needs to log in again
                            print("Token refresh failed on app start")
                            appState.logout()
                        }
                        isCheckingAuthentication = false
                    }
                }
            } else {
                // No token found despite cached login state
                print("No token found despite cached login state")
                appState.logout()
                isCheckingAuthentication = false
            }
        } else {
            // No cached login state, just proceed to login
            isCheckingAuthentication = false
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.blue.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "globe")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("OpenProject")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Mobile")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .padding(.top, 30)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
