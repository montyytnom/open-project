//
//  Reminder.swift
//  Openproject
//
//  Created by A on 3/19/25.
//

import Foundation

struct Reminder: Identifiable, Codable {
    let id: UUID
    let workPackageId: Int
    let workPackageSubject: String
    let reminderDate: Date
    let reminderNote: String
    var isActive: Bool
    
    init(id: UUID = UUID(), workPackageId: Int, workPackageSubject: String, reminderDate: Date, reminderNote: String, isActive: Bool = true) {
        self.id = id
        self.workPackageId = workPackageId
        self.workPackageSubject = workPackageSubject
        self.reminderDate = reminderDate
        self.reminderNote = reminderNote
        self.isActive = isActive
    }
} 