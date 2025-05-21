import Foundation
import SwiftUI

struct NavigationDestination: Equatable {
    let destination: NavigationDestinationType
}

// Navigation destination enum to handle different navigation targets
enum NavigationDestinationType: Equatable {
    case workPackage(id: Int)
    case project(id: Int)
    case comment(id: Int)
    case activity(id: Int)
}