//
//  Notification.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import SwiftUI

struct NotificationCollection: Codable {
    let embedded: NotificationEmbedded
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

struct NotificationEmbedded: Codable {
    let elements: [Notification]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
}

struct Notification: Codable, Identifiable {
    let id: Int
    let reason: String
    var readIAN: Bool
    let message: String?
    let resourceType: String?
    let resourceId: Int?
    let resourceName: String?
    let createdAt: String
    let updatedAt: String?
    let links: NotificationLinks
    
    enum CodingKeys: String, CodingKey {
        case id
        case reason
        case readIAN = "readIAN"
        case message
        case resourceType
        case resourceId
        case resourceName
        case createdAt
        case updatedAt
        case links = "_links"
    }
    
    // Add a debug description for improved logging
    var debugDescription: String {
        return """
        Notification(id: \(id), 
                   reason: \(reason), 
                   readIAN: \(readIAN), 
                   resourceType: \(resourceType ?? "nil"), 
                   resourceId: \(resourceId ?? 0), 
                   resourceName: \(resourceName ?? "nil"))
        """
    }
}

struct NotificationLinks: Codable {
    var actor: Link
    var project: Link?
    var resource: Link?
    var activity: Link?
    var readIAN: Link?
    var unreadIAN: Link?
    
    enum CodingKeys: String, CodingKey {
        case actor
        case project
        case resource
        case activity
        case readIAN
        case unreadIAN
    }
    
    // Add a debug description for improved logging
    var debugDescription: String {
        return """
        NotificationLinks(
            actor: \(actor.href ?? "nil"),
            project: \(project?.href ?? "nil"),
            resource: \(resource?.href ?? "nil"),
            activity: \(activity?.href ?? "nil"),
            readIAN: \(readIAN?.href ?? "nil"),
            unreadIAN: \(unreadIAN?.href ?? "nil")
        )
        """
    }
} 