//
//  ReminderManager.swift
//  Openproject
//
//  Created by A on 3/19/25.
//

import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

class ReminderManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let reminderKey = "workPackageReminders"
    @Published var reminders: [Reminder] = []
    
    init() {
        print("ReminderManager initializing...")
        loadReminders()
        requestNotificationPermission()
        print("ReminderManager loaded \(reminders.count) reminders from UserDefaults")
    }
    
    // Request permission for notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            } else {
                print("Notification permission denied")
            }
        }
    }
    
    // Load reminders from UserDefaults
    private func loadReminders() {
        print("Loading reminders from UserDefaults with key: \(reminderKey)")
        if let data = userDefaults.data(forKey: reminderKey) {
            do {
                let loadedReminders = try JSONDecoder().decode([Reminder].self, from: data)
                self.reminders = loadedReminders
                print("Successfully loaded \(loadedReminders.count) reminders")
            } catch {
                print("Error decoding reminders: \(error)")
                self.reminders = []
            }
        } else {
            print("No reminders data found in UserDefaults")
            self.reminders = []
        }
    }
    
    // Save reminders to UserDefaults
    private func saveReminders() {
        print("Saving \(reminders.count) reminders to UserDefaults")
        do {
            let data = try JSONEncoder().encode(reminders)
            userDefaults.set(data, forKey: reminderKey)
            print("Reminders successfully saved to UserDefaults")
        } catch {
            print("Error encoding reminders: \(error)")
        }
    }
    
    // Add a new reminder
    func addReminder(for workPackage: WorkPackage, date: Date, note: String) -> Reminder {
        print("Adding new reminder for Work Package ID: \(workPackage.id)")
        let newReminder = Reminder(
            workPackageId: workPackage.id,
            workPackageSubject: workPackage.subject,
            reminderDate: date,
            reminderNote: note
        )
        
        reminders.append(newReminder)
        saveReminders()
        scheduleNotification(for: newReminder)
        print("New reminder added and saved with ID: \(newReminder.id)")
        
        return newReminder
    }
    
    // Update an existing reminder
    func updateReminder(_ reminder: Reminder, newDate: Date? = nil, newNote: String? = nil, isActive: Bool? = nil) {
        print("Updating reminder with ID: \(reminder.id)")
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else {
            print("Error: Reminder not found in array")
            return
        }
        
        // Cancel the existing notification
        cancelNotification(for: reminder)
        
        // Create updated reminder
        var updatedReminder = reminder
        
        if let newDate = newDate {
            updatedReminder = Reminder(
                id: reminder.id,
                workPackageId: reminder.workPackageId,
                workPackageSubject: reminder.workPackageSubject,
                reminderDate: newDate,
                reminderNote: newNote ?? reminder.reminderNote,
                isActive: isActive ?? reminder.isActive
            )
            print("Updated reminder date to: \(newDate)")
        } else if let newNote = newNote {
            updatedReminder = Reminder(
                id: reminder.id,
                workPackageId: reminder.workPackageId,
                workPackageSubject: reminder.workPackageSubject,
                reminderDate: reminder.reminderDate,
                reminderNote: newNote,
                isActive: isActive ?? reminder.isActive
            )
            print("Updated reminder note")
        } else if let isActive = isActive {
            updatedReminder = Reminder(
                id: reminder.id,
                workPackageId: reminder.workPackageId,
                workPackageSubject: reminder.workPackageSubject,
                reminderDate: reminder.reminderDate,
                reminderNote: reminder.reminderNote,
                isActive: isActive
            )
            print("Updated reminder active state to: \(isActive)")
        }
        
        // Update the reminder in the array
        reminders[index] = updatedReminder
        saveReminders()
        
        // Schedule notification if the reminder is active
        if updatedReminder.isActive {
            scheduleNotification(for: updatedReminder)
            print("Rescheduled notification for updated reminder")
        } else {
            print("Reminder is inactive, no notification scheduled")
        }
    }
    
    // Remove a reminder
    func removeReminder(_ reminder: Reminder) {
        print("Removing reminder with ID: \(reminder.id)")
        cancelNotification(for: reminder)
        reminders.removeAll { $0.id == reminder.id }
        saveReminders()
        print("Reminder removed and changes saved")
    }
    
    // Get all reminders for a specific work package
    func getRemindersForWorkPackage(id: Int) -> [Reminder] {
        print("Getting reminders for Work Package ID: \(id)")
        let filteredReminders = reminders.filter { $0.workPackageId == id }
        print("Found \(filteredReminders.count) reminders for Work Package ID: \(id)")
        return filteredReminders
    }
    
    // Find a reminder by its UUID
    func findReminderById(_ id: UUID) -> Reminder? {
        print("Looking for reminder with ID: \(id)")
        let reminder = reminders.first { 
            // Print the actual UUID comparison for debugging
            let matches = $0.id == id
            print("Comparing \($0.id) with \(id): \(matches)")
            return matches
        }
        
        if reminder != nil {
            print("✅ Found reminder with ID: \(id)")
        } else {
            print("❌ Could not find reminder with ID: \(id) among \(reminders.count) reminders")
            // Print all available reminders for debugging
            for (index, r) in reminders.enumerated() {
                print("  \(index+1). \(r.id) - WP: \(r.workPackageId) - \(r.reminderDate)")
            }
        }
        
        return reminder
    }
    
    // Schedule a local notification for a reminder
    private func scheduleNotification(for reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = "Work Package Reminder"
        content.subtitle = reminder.workPackageSubject
        content.body = reminder.reminderNote.isEmpty ? "Reminder for this work package" : reminder.reminderNote
        content.sound = UNNotificationSound.default
        
        // Set the badge count
        content.badge = 1
        
        // Create the trigger for the notification
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.reminderDate)
        dateComponents.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create the request with the content and trigger
        let request = UNNotificationRequest(
            identifier: "\(reminder.id)",
            content: content,
            trigger: trigger
        )
        
        // Add the request to the notification center
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reminder notification: \(error.localizedDescription)")
            } else {
                print("Successfully scheduled reminder notification for \(reminder.workPackageSubject) at \(reminder.reminderDate)")
                
                // Post a notification that a reminder has been scheduled
                NotificationCenter.default.post(
                    name: NSNotification.Name("ReminderScheduled"),
                    object: nil,
                    userInfo: ["reminderId": reminder.id]
                )
            }
        }
    }
    
    // Cancel a scheduled notification
    private func cancelNotification(for reminder: Reminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
    }
} 