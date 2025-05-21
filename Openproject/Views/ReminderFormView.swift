//
//  ReminderFormView.swift
//  Openproject
//
//  Created by A on 3/19/25.
//

import SwiftUI

struct ReminderFormView: View {
    @EnvironmentObject private var appState: AppState
    var workPackage: WorkPackage
    @Binding var isPresented: Bool
    var reminderToEdit: Reminder?
    
    @State private var reminderDate: Date
    @State private var reminderTime: Date
    @State private var note: String
    @State private var isActive: Bool
    @State private var errorMessage: String?
    
    init(workPackage: WorkPackage, isPresented: Binding<Bool>, reminderToEdit: Reminder? = nil) {
        print("\n======== ReminderFormView init ========")
        print("WorkPackage ID: \(workPackage.id)")
        if let reminder = reminderToEdit {
            print("✅ Initializing with reminder to edit - ID: \(reminder.id)")
            print("Reminder date: \(reminder.reminderDate)")
            print("Reminder note: \(reminder.reminderNote)")
            print("Reminder is active: \(reminder.isActive)")
        } else {
            print("ℹ️ Initializing for new reminder creation (reminderToEdit is nil)")
        }
        
        self.workPackage = workPackage
        self._isPresented = isPresented
        self.reminderToEdit = reminderToEdit
        
        let initialDate = reminderToEdit?.reminderDate ?? Date().addingTimeInterval(3600 * 24) // Default to tomorrow
        print("Initial date set to: \(initialDate)")
        
        // Extract date components from the reminder date or use defaults
        _reminderDate = State(initialValue: initialDate)
        _reminderTime = State(initialValue: initialDate)
        _note = State(initialValue: reminderToEdit?.reminderNote ?? "")
        _isActive = State(initialValue: reminderToEdit?.isActive ?? true)
        
        print("======== ReminderFormView init complete ========\n")
    }
    
    var body: some View {
        NavigationView {
            Form {
                #if DEBUG
                Text("Debug - Editing Reminder: \(reminderToEdit != nil ? "Yes - ID: \(reminderToEdit!.id)" : "No")")
                    .font(.caption)
                    .foregroundColor(.blue)
                #endif
                
                Section(header: Text("Reminder Details")) {
                    DatePicker("Date", selection: $reminderDate, displayedComponents: .date)
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    
                    TextField("Note", text: $note)
                        .placeholder(when: note.isEmpty) {
                            Text("Optional note about this reminder").foregroundColor(.gray)
                        }
                    
                    Toggle("Active", isOn: $isActive)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                
                Section {
                    if reminderToEdit != nil {
                        Button(action: saveReminder) {
                            Text("Update Reminder")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: deleteReminder) {
                            Text("Delete Reminder")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(8)
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: saveReminder) {
                            Text("Add Reminder")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(reminderToEdit != nil ? "Edit Reminder" : "Add Reminder")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
            .onAppear {
                print("\n======== ReminderFormView appeared ========")
                print("AppState: \(String(describing: appState))")
                print("WorkPackage ID: \(workPackage.id)")
                print("Date state value: \(reminderDate)")
                print("Time state value: \(reminderTime)")
                print("Note state value: \(note)")
                print("isActive state value: \(isActive)")
                
                if let reminder = reminderToEdit {
                    print("Editing reminder with ID: \(reminder.id)")
                    print("Reminder original date: \(reminder.reminderDate)")
                    print("Reminder original note: \(reminder.reminderNote)")
                    print("Reminder original active state: \(reminder.isActive)")
                } else {
                    print("Creating new reminder")
                }
                print("========================================\n")
            }
        }
    }
    
    private func saveReminder() {
        print("\n======== Saving Reminder ========")
        // Combine date and time components
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: reminderDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: reminderTime)
        
        print("Date components: \(dateComponents)")
        print("Time components: \(timeComponents)")
        
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year
        combinedComponents.month = dateComponents.month
        combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour
        combinedComponents.minute = timeComponents.minute
        
        print("Combined components: \(combinedComponents)")
        
        guard let combinedDate = calendar.date(from: combinedComponents) else {
            errorMessage = "Invalid date or time"
            print("Error: Invalid date or time")
            return
        }
        
        print("Combined date: \(combinedDate)")
        
        // Ensure the date is in the future
        if combinedDate <= Date() {
            errorMessage = "Reminder date must be in the future"
            print("Error: Reminder date must be in the future")
            return
        }
        
        if let reminderToEdit = reminderToEdit {
            print("Updating existing reminder with ID: \(reminderToEdit.id)")
            // Update existing reminder
            appState.reminderManager.updateReminder(
                reminderToEdit,
                newDate: combinedDate,
                newNote: note,
                isActive: isActive
            )
        } else {
            print("Creating new reminder")
            // Create new reminder
            let newReminder = appState.reminderManager.addReminder(
                for: workPackage,
                date: combinedDate,
                note: note
            )
            print("Created new reminder with ID: \(newReminder.id)")
        }
        
        print("Save complete, dismissing form")
        print("==============================\n")
        isPresented = false
    }
    
    private func deleteReminder() {
        if let reminderToEdit = reminderToEdit {
            appState.reminderManager.removeReminder(reminderToEdit)
            
            // Post notification that reminder was deleted so parent views can update
            NotificationCenter.default.post(name: NSNotification.Name("ReminderDeleted"), object: reminderToEdit.id)
        }
        isPresented = false
    }
}

// Helper extension for placeholder text in TextField
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 