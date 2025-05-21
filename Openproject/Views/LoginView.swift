//
//  LoginView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
import AuthenticationServices
import WebKit
import UserNotifications

// Import models directly

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShowingWebView = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    VStack(spacing: 24) {
                        // Logo and header
                        VStack(spacing: 16) {
                            Image(systemName: "power.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .foregroundColor(.blue)
                            Text("OpenProject")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Mobile Client v1")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                
                            Text("https://project.anyitthing.com")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        // Login button
                        Button(action: prepareOAuthLogin) {
                            HStack {
                                Text("Sign In with OpenProject")
                                    .fontWeight(.semibold)
                                
                                if isLoading {
                                    ProgressView()
                                        .padding(.leading, 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                    
                    if isShowingWebView {
                        OAuthWebView(
                            url: generateOAuthURL(),
                            onCancel: {
                                isShowingWebView = false
                            },
                            onCode: { code in
                                isShowingWebView = false
                                exchangeCodeForToken(code)
                            }
                        )
                        .transition(.move(edge: .bottom))
                    }
                }
            }
            .navigationBarHidden(true)
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                print("!!! DEBUG_LOGIN: LoginView appeared")
                print("!!! DEBUG_LOGIN: API Base URL: \(appState.apiBaseURL)")
                print("!!! DEBUG_LOGIN: OAuth Base URL: \(appState.oauthBaseURL)")
                
                ConsoleLog.debug("LoginView appeared")
                ConsoleLog.info("API Base URL: \(appState.apiBaseURL)")
                ConsoleLog.info("OAuth Base URL: \(appState.oauthBaseURL)")
            }
        }
    }
    
    private func prepareOAuthLogin() {
        // Use the known working server URL from OAuthService.swift
        let baseURL = "https://project.anyitthing.com/"
        
        ConsoleLog.debug("OAuth login preparation started")
        ConsoleLog.info("Using base URL: \(baseURL)")
        
        // Set the base URLs
        appState.apiBaseURL = "\(baseURL)api/v3"
        appState.oauthBaseURL = "\(baseURL)oauth"
        
        ConsoleLog.info("API Base URL: \(appState.apiBaseURL)")
        ConsoleLog.info("OAuth Base URL: \(appState.oauthBaseURL)")
        
        // Show the OAuth web view
        isShowingWebView = true
    }
    
    private func generateOAuthURL() -> URL {
        let authURL = "\(appState.oauthBaseURL)/authorize"
        let redirectURI = "openproject://callback" // Match working implementation
        
        // Add a state parameter to prevent CSRF
        let state = UUID().uuidString
        
        ConsoleLog.debug("Generating OAuth URL with state: \(state)")
        
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appState.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "api_v3")
        ]
        
        ConsoleLog.debug("OAuth URL generated: \(components.url?.absoluteString ?? "invalid URL")")
        return components.url!
    }
    
    private func exchangeCodeForToken(_ code: String) {
        isLoading = true
        
        let tokenURL = "\(appState.oauthBaseURL)/token"
        let redirectURI = "openproject://callback" // Match working implementation
        
        ConsoleLog.debug("Exchanging code for token")
        ConsoleLog.info("Token endpoint: \(tokenURL)")
        
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: String] = [
            "client_id": appState.clientId,
            "client_secret": appState.clientSecret,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        let parameterString = parameters.map { key, value in
            return "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }.joined(separator: "&")
        
        request.httpBody = parameterString.data(using: .utf8)
        
        // Create a completely insecure session just for token exchange
        let insecureSessionConfig = URLSessionConfiguration.default
        
        // Create a one-time trust-all-certificates delegate
        class TokenExchangeDelegate: NSObject, URLSessionDelegate {
            override init() {
                super.init()
                ConsoleLog.debug("TokenExchangeDelegate initialized")
            }
            
            func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                ConsoleLog.debug("TokenExchange: SSL Challenge received for \(challenge.protectionSpace.host)")
                // Accept ANY certificate unconditionally
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                ConsoleLog.debug("TokenExchange: SSL Task Challenge received for \(challenge.protectionSpace.host)")
                // Accept ANY certificate unconditionally
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
        }
        
        let insecureSession = URLSession(configuration: insecureSessionConfig, delegate: TokenExchangeDelegate(), delegateQueue: nil)
        
        ConsoleLog.info("Using insecure session for token exchange with URL: \(request.url?.absoluteString ?? "unknown")")
        insecureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    ConsoleLog.error("Token exchange error: \(error.localizedDescription)")
                    self.alertMessage = "Error: \(error.localizedDescription)"
                    self.showAlert = true
                    return
                }
                
                guard let response = response as? HTTPURLResponse else {
                    ConsoleLog.error("Token exchange error: No response received")
                    self.alertMessage = "Error: No response received"
                    self.showAlert = true
                    return
                }
                
                ConsoleLog.debug("Token exchange response status: \(response.statusCode)")
                
                if response.statusCode != 200 {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        ConsoleLog.error("Token exchange error response: \(responseString)")
                    }
                    self.alertMessage = "Error: HTTP \(response.statusCode)"
                    self.showAlert = true
                    return
                }
                
                guard let data = data else {
                    ConsoleLog.error("No data received from server")
                    self.alertMessage = "No data received from server"
                    self.showAlert = true
                    return
                }
                
                do {
                    let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                    
                    // Save token information
                    self.appState.accessToken = tokenResponse.accessToken
                    self.appState.refreshToken = tokenResponse.refreshToken
                    
                    // Calculate expiration date
                    let expirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                    self.appState.tokenExpirationDate = expirationDate
                    
                    ConsoleLog.info("Token successfully obtained. Expires in: \(tokenResponse.expiresIn) seconds")
                    
                    // Fetch user info
                    self.fetchUserInfo()
                } catch {
                    ConsoleLog.error("Failed to parse token response: \(error.localizedDescription)")
                    self.alertMessage = "Failed to parse token response: \(error.localizedDescription)"
                    if let responseData = String(data: data, encoding: .utf8) {
                        ConsoleLog.error("Response data: \(responseData)")
                        self.alertMessage += "\n\nResponse: \(responseData)"
                    }
                    self.showAlert = true
                }
            }
        }.resume()
    }
    
    private func fetchUserInfo() {
        guard let token = appState.accessToken else {
            ConsoleLog.error("Cannot fetch user info: No access token available")
            return
        }
        
        let userURL = "\(appState.apiBaseURL)/users/me"
        ConsoleLog.debug("Fetching user info from: \(userURL)")
        
        var request = URLRequest(url: URL(string: userURL)!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.trustingSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    ConsoleLog.error("Error fetching user info: \(error.localizedDescription)")
                    self.alertMessage = "Error fetching user info: \(error.localizedDescription)"
                    self.showAlert = true
                    return
                }
                
                guard let response = response as? HTTPURLResponse else {
                    ConsoleLog.error("User info error: No HTTP response received")
                    return
                }
                
                ConsoleLog.debug("User info response status: \(response.statusCode)")
                
                guard let data = data else {
                    ConsoleLog.error("No user data received")
                    self.alertMessage = "No user data received"
                    self.showAlert = true
                    return
                }
                
                // Log the raw user data response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    ConsoleLog.debug("Raw user data response: \(responseString)")
                }
                
                do {
                    let user = try JSONDecoder().decode(User.self, from: data)
                    self.appState.user = user
                    
                    ConsoleLog.info("User data successfully retrieved for: \(user.firstName) \(user.lastName)")
                    ConsoleLog.info("User admin status: \(user.admin == nil ? "nil" : String(describing: user.admin!))")
                    
                    // Save all user data to keychain
                    self.appState.saveUserData()
                    
                    // Mark as logged in
                    self.appState.isLoggedIn = true
                    
                    ConsoleLog.info("Login process completed successfully")
                } catch {
                    ConsoleLog.error("Failed to parse user data: \(error.localizedDescription)")
                    
                    // More detailed error logging
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            ConsoleLog.error("Key not found: \(key.stringValue), context: \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            ConsoleLog.error("Type mismatch: expected \(type), context: \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            ConsoleLog.error("Value not found: expected \(type), context: \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            ConsoleLog.error("Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            ConsoleLog.error("Unknown decoding error: \(decodingError)")
                        }
                    }
                    
                    self.alertMessage = "Failed to parse user data: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }.resume()
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct OAuthWebView: UIViewControllerRepresentable {
    let url: URL
    let onCancel: () -> Void
    let onCode: (String) -> Void
    
    class Coordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
        let parent: OAuthWebView
        var authSession: ASWebAuthenticationSession?
        
        init(parent: OAuthWebView) {
            self.parent = parent
            ConsoleLog.debug("OAuthWebView Coordinator initialized")
        }
        
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            ConsoleLog.debug("Providing presentation anchor for OAuth web authentication")
            return UIApplication.shared.windows.first { $0.isKeyWindow }!
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        ConsoleLog.debug("Setting up OAuthWebView with URL: \(url.absoluteString)")
        
        // Set up the authentication session
        let authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "openproject",
            completionHandler: { callbackURL, error in
                if let error = error {
                    ConsoleLog.error("OAuth Error: \(error.localizedDescription)")
                    onCancel()
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    ConsoleLog.error("No callback URL received")
                    onCancel()
                    return
                }
                
                ConsoleLog.debug("Received callback URL: \(callbackURL)")
                
                guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems,
                      let codeItem = queryItems.first(where: { $0.name == "code" }),
                      let code = codeItem.value else {
                    ConsoleLog.error("Could not extract code from callback URL")
                    onCancel()
                    return
                }
                
                ConsoleLog.info("Successfully extracted OAuth authorization code")
                onCode(code)
            }
        )
        
        authSession.presentationContextProvider = context.coordinator
        // Set to true to ensure login state is NOT preserved across app sessions
        authSession.prefersEphemeralWebBrowserSession = true
        
        // Start the authentication session
        if authSession.start() {
            ConsoleLog.info("Authentication session started successfully")
        } else {
            ConsoleLog.error("Failed to start authentication session")
            onCancel()
        }
        
        // Store the auth session in the coordinator to prevent it from being deallocated
        context.coordinator.authSession = authSession
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to do here
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AppState())
    }
} 
