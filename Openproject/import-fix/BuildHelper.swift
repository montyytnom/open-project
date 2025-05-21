import Foundation
import SwiftUI
import Combine

// This file is a build helper to ensure that all types are properly imported
// The Xcode compiler should now be able to find these types during build

// Force the compiler to recognize these types during build
typealias ForceImport_AppState = AppState
typealias ForceImport_Project = Project
// Removed User alias to fix ambiguity
typealias ForceImport_WorkPackage = WorkPackage
typealias ForceImport_WorkPackageType = WorkPackageType
typealias ForceImport_WorkPackageStatus = WorkPackageStatus
typealias ForceImport_WorkPackagePriority = WorkPackagePriority
typealias ForceImport_StatusCollection = StatusCollection
typealias ForceImport_TypeCollection = TypeCollection
typealias ForceImport_PriorityCollection = PriorityCollection
typealias ForceImport_APIErrorResponse = APIErrorResponse
typealias ForceImport_Comment = Comment
// Removed Attachment alias to fix ambiguity
typealias ForceImport_Link = Link 