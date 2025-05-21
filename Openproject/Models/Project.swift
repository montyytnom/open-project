//
//  Project.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import SwiftUI

struct ProjectCollection: Codable {
    let embedded: ProjectEmbedded
    let total: Int
    let count: Int
    let pageSize: Int
    let offset: Int
    let links: ProjectCollectionLinks
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
        case total
        case count
        case pageSize
        case offset
        case links = "_links"
    }
}

struct ProjectCollectionLinks: Codable {
    let selfLink: Link
    let jumpTo: Link?
    let changeSize: Link?
    let representations: [Link]?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case jumpTo
        case changeSize
        case representations
    }
}

struct ProjectEmbedded: Codable {
    let elements: [Project]
    
    enum CodingKeys: String, CodingKey {
        case elements = "elements"
    }
}

struct Project: Codable, Identifiable {
    let id: Int
    let identifier: String
    let name: String
    let active: Bool
    let isPublic: Bool
    let description: ProjectDescription?
    let createdAt: String
    let updatedAt: String
    let statusExplanation: ProjectDescription?
    let customField1: ProjectDescription?
    let customField2: ProjectDescription?
    let customField6: ProjectDescription?
    let links: ProjectLinks
    
    enum CodingKeys: String, CodingKey {
        case id
        case identifier
        case name
        case active
        case isPublic = "public"
        case description
        case createdAt
        case updatedAt
        case statusExplanation
        case customField1
        case customField2
        case customField6
        case links = "_links"
    }
}

struct ProjectDescription: Codable {
    let format: String
    let raw: String
    let html: String
}

struct ProjectLinks: Codable {
    let selfLink: Link
    let createWorkPackage: Link?
    let createWorkPackageImmediately: Link?
    let workPackages: Link?
    let storages: Link?
    let categories: Link?
    let versions: Link?
    let memberships: Link?
    let types: Link?
    let update: Link?
    let updateImmediately: Link?
    let delete: Link?
    let schema: Link?
    let status: Link?
    let customField1: Link?
    let customField2: Link?
    let customField3: Link?
    let customField6: Link?
    let ancestors: Link?
    let projectStorages: Link?
    let parent: Link?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case createWorkPackage
        case createWorkPackageImmediately
        case workPackages
        case storages
        case categories
        case versions
        case memberships
        case types
        case update
        case updateImmediately
        case delete
        case schema
        case status
        case customField1
        case customField2
        case customField3
        case customField6
        case ancestors
        case projectStorages
        case parent
    }
}

struct ProjectStatus: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    
    static let onTrack = ProjectStatus(id: "on_track", name: "On track")
    static let atRisk = ProjectStatus(id: "at_risk", name: "At risk")
    static let offTrack = ProjectStatus(id: "off_track", name: "Off track")
    static let notStarted = ProjectStatus(id: "not_started", name: "Not started")
    static let finished = ProjectStatus(id: "finished", name: "Finished")
    static let discontinued = ProjectStatus(id: "discontinued", name: "Discontinued")
    
    static let allStatuses = [onTrack, atRisk, offTrack, notStarted, finished, discontinued]
    
    // Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable implementation
    static func == (lhs: ProjectStatus, rhs: ProjectStatus) -> Bool {
        return lhs.id == rhs.id
    }
} 