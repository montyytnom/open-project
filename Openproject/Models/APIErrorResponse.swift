//
//  APIErrorResponse.swift
//  Openproject
//
//  Created by A on 3/19/25.
//

import Foundation

// API error response
struct APIErrorResponse: Codable {
    let message: String?
    let errorIdentifier: String?
    let errorType: String?
    
    enum CodingKeys: String, CodingKey {
        case message
        case errorIdentifier
        case errorType = "_type"
    }
} 