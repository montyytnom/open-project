import Foundation
import SwiftUI

struct Link: Codable {
    let href: String?
    let title: String?
    let templated: Bool?
    let method: String?
    
    enum CodingKeys: String, CodingKey {
        case href
        case title
        case templated
        case method
    }
} 