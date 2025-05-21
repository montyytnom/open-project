//
//  WorkPackage.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct WorkPackageCollection: Codable {
    let embedded: WorkPackageEmbedded
    let count: Int
    let total: Int
    let pageSize: Int
    let offset: Int
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
        case count
        case total
        case pageSize
        case offset
    }
}

struct WorkPackageEmbedded: Codable {
    let elements: [WorkPackage]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
}

struct WorkPackage: Codable, Identifiable {
    let id: Int
    var subject: String
    var description: ProjectDescription?
    let startDate: String?
    let dueDate: String?
    let estimatedTime: String?
    let spentTime: String?
    let percentageDone: Int?
    let createdAt: String
    var updatedAt: String
    var lockVersion: Int
    var links: WorkPackageLinks
    
    // Computed property to get the addAttachment href
    var addAttachmentLink: String {
        return links.addAttachment?.href ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case description
        case startDate
        case dueDate
        case estimatedTime
        case spentTime
        case percentageDone
        case createdAt
        case updatedAt
        case lockVersion
        case links = "_links"
    }
}

struct WorkPackageLinks: Codable {
    let selfLink: Link
    let project: Link?
    var status: Link?
    let type: Link?
    var priority: Link?
    var assignee: Link?
    let responsible: Link?
    let author: Link?
    let activities: Link?
    let watchers: Link?
    let attachments: Link?
    let relations: Link?
    let revisions: Link?
    let delete: Link?
    let update: Link?
    let updateImmediately: Link?
    let addAttachment: Link?
    let addComment: Link?
    let addWatcher: Link?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case project
        case status
        case type
        case priority
        case assignee
        case responsible
        case author
        case activities
        case watchers
        case attachments
        case relations
        case revisions
        case delete
        case update
        case updateImmediately
        case addAttachment
        case addComment
        case addWatcher
    }
}

struct WorkPackageStatus: Codable, Identifiable {
    let id: Int
    let name: String
    let isClosed: Bool
    let isDefault: Bool
    let position: Int
    let color: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isClosed
        case isDefault
        case position
        case color
    }
}

struct WorkPackagePriority: Codable, Identifiable {
    let id: Int
    let name: String
    let position: Int
    let color: String?
    let isDefault: Bool
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case color
        case isDefault
        case isActive
    }
}

struct WorkPackageType: Codable, Identifiable {
    let id: Int
    let name: String
    let color: String
    let position: Int
    let isDefault: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case position
        case isDefault
    }
}

struct ActivityComment: Codable {
    let format: String
    let raw: String
    let html: String
}

struct SimpleUser: Codable, Identifiable {
    let id: Int
    let name: String
}

struct SimpleProject: Codable, Identifiable {
    let id: Int
    let name: String
}

// Status collection
struct StatusCollection: Codable {
    let embedded: StatusEmbedded
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

struct StatusEmbedded: Codable {
    let elements: [WorkPackageStatus]
}

// Type collection
struct TypeCollection: Codable {
    let embedded: TypeEmbedded
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

struct TypeEmbedded: Codable {
    let elements: [WorkPackageType]
}

// Priority collection
struct PriorityCollection: Codable {
    let embedded: PriorityEmbedded
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

struct PriorityEmbedded: Codable {
    let elements: [WorkPackagePriority]
}

// Comment related structures
struct Comment: Codable {
    let format: String?
    let raw: String?
    let html: String?
    
    enum CodingKeys: String, CodingKey {
        case format
        case raw
        case html
    }
}

// Add a DetailItem struct to handle each element in the details array
struct DetailItem: Codable {
    let format: String
    let raw: String
    let html: String
}

struct Activity: Codable, Identifiable {
    let id: Int
    let type: String
    let createdAt: Date
    let user: ActivityUser
    let comment: Comment?
    let details: [DetailItem]?
    let version: Int?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case createdAt = "createdAt"
        case links = "_links"
        case comment
        case details
        case version
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        
        // Create multiple date formatters to handle different formats
        let iso8601Full = ISO8601DateFormatter()
        let iso8601WithMilliseconds = ISO8601DateFormatter()
        iso8601WithMilliseconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Custom formatter for other possible formats
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" // Standard format without fractional seconds
        
        // Handle date decoding with multiple fallbacks
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            if let date = iso8601WithMilliseconds.date(from: dateString) {
                createdAt = date
            } else if let date = iso8601Full.date(from: dateString) {
                createdAt = date
            } else if let date = customFormatter.date(from: dateString) {
                createdAt = date
            } else {
                print("⚠️ Failed to parse date for activity ID: \(id)")
                createdAt = Date()
            }
        } else {
            print("⚠️ No date string found for activity ID: \(id)")
            createdAt = Date()
        }
        
        // Handle updatedAt date with multiple formatters
        if let dateString = try? container.decode(String.self, forKey: .updatedAt) {
            if let date = iso8601WithMilliseconds.date(from: dateString) {
                updatedAt = date
            } else if let date = iso8601Full.date(from: dateString) {
                updatedAt = date
            } else if let date = customFormatter.date(from: dateString) {
                updatedAt = date
            } else {
                print("⚠️ Failed to parse updatedAt date for activity ID: \(id)")
                updatedAt = nil
            }
        } else {
            updatedAt = nil
        }
        
        // Extract user from links
        let linksContainer = try container.nestedContainer(keyedBy: ActivityLinkKeys.self, forKey: .links)
        if let userLink = try? linksContainer.nestedContainer(keyedBy: ActivityUserLinkKeys.self, forKey: .user) {
            let href = try userLink.decode(String.self, forKey: .href)
            
            // Get either title or name as they might be used in different API versions
            var userName = "Unknown User"
            if let title = try? userLink.decode(String.self, forKey: .title) {
                userName = title
            } else if let name = try? userLink.decode(String.self, forKey: .name) {
                userName = name
            } else {
                // Extract user ID from href as fallback
                let components = href.split(separator: "/")
                if let userId = components.last {
                    userName = "User \(userId)"
                }
            }
            
            user = ActivityUser(href: href, name: userName)
        } else {
            // Fallback user if not in links
            user = ActivityUser(href: "", name: "System")
        }
        
        // Handle optional fields with proper error handling
        comment = try container.decodeIfPresent(Comment.self, forKey: .comment)
        details = try container.decodeIfPresent([DetailItem].self, forKey: .details)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(version, forKey: .version)
        
        // Encode dates
        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
        if let updatedDate = updatedAt {
            try container.encode(formatter.string(from: updatedDate), forKey: .updatedAt)
        }
        
        // Encode user in links
        var linksContainer = container.nestedContainer(keyedBy: ActivityLinkKeys.self, forKey: .links)
        var userContainer = linksContainer.nestedContainer(keyedBy: ActivityUserLinkKeys.self, forKey: .user)
        try userContainer.encode(user.href, forKey: .href)
        try userContainer.encode(user.name, forKey: .title)
        
        // Try to encode name too for better compatibility
        try userContainer.encode(user.name, forKey: .name)
        
        // Encode optional fields
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(details, forKey: .details)
    }
    
    enum ActivityLinkKeys: String, CodingKey {
        case user
    }
    
    enum ActivityUserLinkKeys: String, CodingKey {
        case href
        case title
        case name
    }
}

// Add a user cache singleton to fetch and store user information
class UserCache: ObservableObject {
    static let shared = UserCache()
    @Published private var users = [String: String]() // href -> name
    private var fetchingUsers = Set<String>() // Track which users we're currently fetching
    private var token: String? = nil
    
    private init() {
        // Register for token updates
        NotificationCenter.default.addObserver(self, selector: #selector(tokenUpdated(_:)), name: NSNotification.Name("TokenUpdated"), object: nil)
    }
    
    @objc private func tokenUpdated(_ notification: NSNotification) {
        if let token = notification.object as? String {
            self.token = token
            print("✅ Token updated in UserCache")
        }
    }
    
    func setToken(_ token: String) {
        self.token = token
        print("✅ Token set in UserCache: \(token.prefix(10))...")
        
        // Notify that we have a token now
        NotificationCenter.default.post(name: NSNotification.Name("TokenUpdated"), object: token)
    }
    
    func getName(forHref href: String) -> String {
        // Check if we already have the user in cache
        if let name = users[href] {
            return name
        }
        
        // Extract the user ID from href
        let components = href.split(separator: "/")
        guard let userId = components.last, !fetchingUsers.contains(href) else {
            return "User \(components.last ?? "Unknown")"
        }
        
        // Mark this user as being fetched
        fetchingUsers.insert(href)
        
        DispatchQueue.main.async {
            self.fetchUserDetails(href: href, userId: String(userId))
        }
        
        // Return temporary value while loading
        return "User \(userId)"
    }
    
    private func fetchUserDetails(href: String, userId: String) {
        guard let token = self.token, !token.isEmpty else {
            print("⚠️ No token available for user API request. Check that setToken was called.")
            self.fetchingUsers.remove(href)
            return
        }
        
        // Construct the API URL for the user - use the full user API endpoint
        let baseURL = URL(string: "https://project.anyitthing.com")!
        let userURL = baseURL.appendingPathComponent(href)
        
        print("🔍 Fetching user data from: \(userURL.absoluteString) with token: \(token.prefix(10))...")
        
        // Create a proper request with authentication
        var request = URLRequest(url: userURL)
        
        // Use Bearer token authentication which is used by most API calls in the app
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Fetch the user info with proper auth
        URLSession.shared.dataTask(with: request) {  data, response, error in
            
            
            // Debug response
            if let httpResponse = response as? HTTPURLResponse {
                print("👤 User API HTTP status: \(httpResponse.statusCode)")
            }
            
            if let data = data, let dataSize = data.count as? Int {
                print("📦 User API data size: \(dataSize) bytes")
                
                // Print a preview of the response
                if let jsonString = String(data: data, encoding: .utf8) {
                    let previewLength = min(jsonString.count, 200)
                    let preview = jsonString.prefix(previewLength) + (jsonString.count > previewLength ? "..." : "")
                    print("📄 User API response preview: \(preview)")
                }
            }
            
            // Clean up regardless of result
            defer {
                self.fetchingUsers.remove(href)
            }
            
            // Check for errors or invalid data
            guard let data = data, error == nil else {
                print("❌ Error fetching user data: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let name = json?["name"] as? String {
                    print("✅ Successfully fetched name for user \(userId): \(name)")
                    
                    // Store in cache
                    DispatchQueue.main.async {
                        self.users[href] = name
                        // Post notification that user data has been updated
                        NotificationCenter.default.post(name: NSNotification.Name("UserCacheUpdated"), object: nil)
                    }
                } else {
                    print("❌ No name found in user JSON: \(json ?? [:])")
                }
            } catch {
                print("❌ Failed to parse user JSON: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct ActivityUser: Codable {
    let href: String
    let name: String
    
    // Add a computed property to get real name from cache
    var displayName: String {
        if name == "User \(href.split(separator: "/").last ?? "")" {
            return UserCache.shared.getName(forHref: href)
        }
        return name
    }
}

struct ActivityUserLinks: Codable {
    let selfLink: Link?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
    }
}

struct ActivityCollection: Codable {
    let type: String
    let total: Int
    let count: Int
    let embedded: ActivityEmbedded
    
    enum CodingKeys: String, CodingKey {
        case type = "_type"
        case total
        case count
        case embedded = "_embedded"
    }
}

struct ActivityEmbedded: Codable {
    let elements: [Activity]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
}

// Attachment related structures
struct Attachment: Codable, Identifiable {
    let id: Int
    let type: String
    let fileName: String
    let fileSize: Int
    let description: Comment?
    let contentType: String
    let createdAt: Date
    let href: String
    let digest: DigestInfo?
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case fileName
        case fileSize
        case description
        case contentType
        case createdAt
        case links = "_links"
        case digest
        case status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileSize = try container.decode(Int.self, forKey: .fileSize)
        description = try container.decodeIfPresent(Comment.self, forKey: .description)
        contentType = try container.decode(String.self, forKey: .contentType)
        status = try container.decode(String.self, forKey: .status)
        digest = try container.decodeIfPresent(DigestInfo.self, forKey: .digest)
        
        // Handle date decoding with fallback
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            // Try multiple date formats
            let iso8601Full = ISO8601DateFormatter()
            
            // Create a formatter that can handle milliseconds
            let iso8601WithMilliseconds = ISO8601DateFormatter()
            iso8601WithMilliseconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Create a standard date formatter for other formats
            let standardFormatter = DateFormatter()
            standardFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            
            if let date = iso8601WithMilliseconds.date(from: dateString) {
                createdAt = date
            } else if let date = iso8601Full.date(from: dateString) {
                createdAt = date
            } else if let date = standardFormatter.date(from: dateString) {
                createdAt = date
            } else {
                print("⚠️ Failed to parse date for attachment ID: \(id). Date string: \(dateString)")
                createdAt = Date()
            }
        } else {
            // Fallback to current date if parsing fails
            print("⚠️ Failed to parse date for attachment ID: \(id)")
            createdAt = Date()
        }
        
        // Handle download location from _links section
        let linksContainer = try container.nestedContainer(keyedBy: AttachmentLinkKeys.self, forKey: .links)
        if let downloadLocation = try? linksContainer.nestedContainer(keyedBy: AttachmentDownloadKeys.self, forKey: .downloadLocation) {
            href = try downloadLocation.decode(String.self, forKey: .href)
        } else if let staticDownloadLocation = try? linksContainer.nestedContainer(keyedBy: AttachmentDownloadKeys.self, forKey: .staticDownloadLocation) {
            href = try staticDownloadLocation.decode(String.self, forKey: .href)
        } else {
            href = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(digest, forKey: .digest)
        
        // Encode date
        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
        
        // Encode links
        var linksContainer = container.nestedContainer(keyedBy: AttachmentLinkKeys.self, forKey: .links)
        
        // Add download location link
        var downloadContainer = linksContainer.nestedContainer(keyedBy: AttachmentDownloadKeys.self, forKey: .downloadLocation)
        try downloadContainer.encode(href, forKey: .href)
        
        // Also add it as static download location for compatibility
        var staticContainer = linksContainer.nestedContainer(keyedBy: AttachmentDownloadKeys.self, forKey: .staticDownloadLocation)
        try staticContainer.encode(href, forKey: .href)
    }
    
    enum AttachmentLinkKeys: String, CodingKey {
        case downloadLocation
        case staticDownloadLocation
    }
    
    enum AttachmentDownloadKeys: String, CodingKey {
        case href
    }
}

struct DigestInfo: Codable {
    let algorithm: String
    let hash: String
}

struct AttachmentCollection: Codable {
    let embedded: AttachmentEmbedded
    let total: Int
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
        case total
        case count
    }
}

struct AttachmentEmbedded: Codable {
    let elements: [Attachment]
}

// Time Entry model
struct TimeEntry: Codable, Identifiable {
    let id: Int
    let hours: Double
    let comment: Comment?
    let spentOn: String
    let createdAt: String
    let updatedAt: String
    let links: TimeEntryLinks
    
    enum CodingKeys: String, CodingKey {
        case id
        case hours
        case comment
        case spentOn = "spentOn"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
        case links = "_links"
    }
    
    struct Comment: Codable {
        let format: String
        let raw: String
        let html: String
    }
}

struct TimeEntryLinks: Codable {
    let selfLink: Link
    let workPackage: Link?
    let project: Link?
    let user: Link?
    let activity: Link?
    let delete: Link?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case workPackage = "workPackage"
        case project = "project"
        case user = "user"
        case activity = "activity"
        case delete = "delete"
    }
}

// Time Entry collection
struct TimeEntryCollection: Codable {
    let embedded: TimeEntryEmbedded
    let total: Int
    let count: Int
    let links: TimeEntryCollectionLinks
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
        case total
        case count
        case links = "_links"
    }
}

struct TimeEntryEmbedded: Codable {
    let elements: [TimeEntry]
}

struct TimeEntryCollectionLinks: Codable {
    let selfLink: Link
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
    }
}

// Activity model for time tracking
struct TimeEntryActivity: Codable, Identifiable {
    let id: Int
    let name: String
    let position: Int
    let isDefault: Bool
    let links: TimeEntryActivityLinks
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case isDefault = "default"
        case links = "_links"
    }
}

struct TimeEntryActivityLinks: Codable {
    let selfLink: Link
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
    }
}

struct TimeEntryActivityCollection: Codable {
    let embedded: TimeEntryActivityEmbedded
    let total: Int
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
        case total
        case count
    }
}

struct TimeEntryActivityEmbedded: Codable {
    let elements: [TimeEntryActivity]
} 