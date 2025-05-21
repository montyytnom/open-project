import Foundation
import SwiftUI

// Models for working with custom fields
struct CustomField: Codable, Identifiable {
    let id: Int
    let name: String
    let fieldFormat: String
    let required: Bool
    let _links: CustomFieldLinks
    
    var customOptions: [CustomOption] = []
    
    enum CodingKeys: String, CodingKey {
        case id, name, fieldFormat, required, _links
    }
}

struct CustomFieldLinks: Codable {
    let selfLink: Link
    let options: Link?
    
    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
        case options
    }
}

struct CustomOption: Codable, Identifiable, Hashable {
    let id: Int
    let value: String
    let _links: CustomOptionLinks
    
    var href: String {
        return _links.`self`.href ?? "/api/v3/custom_options/\(id)"
    }
    
    // Implementing Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CustomOption, rhs: CustomOption) -> Bool {
        return lhs.id == rhs.id
    }
}

struct CustomOptionLinks: Codable {
    let `self`: Link
}

struct CustomFieldCollection: Codable {
    let _embedded: CustomFieldEmbedded
    
    var elements: [CustomField] {
        return _embedded.elements
    }
}

struct CustomFieldEmbedded: Codable {
    let elements: [CustomField]
}

struct CustomOptionCollection: Codable {
    let _embedded: CustomOptionEmbedded
    
    var elements: [CustomOption] {
        return _embedded.elements
    }
}

struct CustomOptionEmbedded: Codable {
    let elements: [CustomOption]
} 