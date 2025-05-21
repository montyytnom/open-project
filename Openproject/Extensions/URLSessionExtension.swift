import Foundation

class SSLTrustManager: NSObject, URLSessionDelegate {
    override init() {
        super.init()
        ConsoleLog.debug("SSLTrustManager initialized - will accept all SSL challenges for anyitthing.com")
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // For the specific domain with certificate issues
        if challenge.protectionSpace.host.contains("anyitthing.com") {
            ConsoleLog.debug("SSL Challenge received for \(challenge.protectionSpace.host) - accepting unconditionally")
            // Accept ANY certificate for this domain unconditionally
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            return
        }
        
        // Default handling for other domains
        ConsoleLog.debug("SSL Challenge received for \(challenge.protectionSpace.host) - using default handling")
        completionHandler(.performDefaultHandling, nil)
    }
    
    // Add authentication method for Basic Auth
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Handle all SSL challenges for our problematic domain
        if challenge.protectionSpace.host.contains("anyitthing.com") {
            ConsoleLog.debug("SSL Task Challenge received for \(challenge.protectionSpace.host) - accepting unconditionally")
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            return
        }
        
        ConsoleLog.debug("SSL Task Challenge received for \(challenge.protectionSpace.host) - using default handling")
        completionHandler(.performDefaultHandling, nil)
    }
}

extension URLSession {
    static let trustingSession: URLSession = {
        ConsoleLog.info("Creating trustingSession with SSLTrustManager for anyitthing.com domain")
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil // Disable cache
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Force reload
        let trustManager = SSLTrustManager()
        return URLSession(configuration: configuration, delegate: trustManager, delegateQueue: nil)
    }()
} 