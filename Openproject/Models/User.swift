//
//  User.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import SwiftUI

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let firstName: String
    let lastName: String
    let email: String?
    let avatar: String?
    let status: String
    let language: String
    let admin: Bool?
    let createdAt: String
    let updatedAt: String
    
    // Computed property to safely check admin status
    var isAdmin: Bool {
        return admin ?? false
    }
    
    // Initializer with default values for optional fields
    init(id: Int, name: String, firstName: String, lastName: String, email: String? = nil, 
         avatar: String? = nil, status: String, language: String, admin: Bool? = nil, 
         createdAt: String, updatedAt: String) {
        self.id = id
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.avatar = avatar
        self.status = status
        self.language = language
        self.admin = admin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstName
        case lastName
        case email
        case avatar
        case status
        case language
        case admin
        case createdAt
        case updatedAt
    }
}

struct UserCollection: Codable {
    let embedded: UserEmbedded
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

struct UserEmbedded: Codable {
    let elements: [User]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
} 