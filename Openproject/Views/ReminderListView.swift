//
//  ReminderListView.swift
//  Openproject
//
//  Created by A on 3/19/25.
//

import SwiftUI

#if DEBUG
import os.log
#endif

struct ReminderListView: View {
    @EnvironmentObject private var appState: AppState
    var workPackage: WorkPackage
    @Binding var isPresented: Bool
    @State private var showAddReminder = false
    @State private var reminderToEdit: Reminder? = nil
    
    // Debug state
    @State private var lastSelectedReminderId: UUID?
    
    var body: some View {
        NavigationView {
            VStack {
                // Debug Text to show if appState or workPackage are nil
                #if DEBUG
                Text("Debug: WP ID: \(workPackage.id), Total reminders: \(appState.reminderManager.reminders.count)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                #endif
                
                List {
                    if appState.reminderManager.getRemindersForWorkPackage(id: workPackage.id).isEmpty {
                        VStack {
                            Text("No reminders set for this work package")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                            
                            #if DEBUG
                            // Debug button to create a test reminder
                            Button(action: {
                                print("Creating a test reminder for debugging")
                                let testReminder = appState.reminderManager.addReminder(
                                    for: workPackage,
                                    date: Date().addingTimeInterval(3600), // 1 hour from now
                                    note: "Test reminder created for debugging"
                                )
                                print("Created test reminder with ID: \(testReminder.id)")
                            }) {
                                Text("Create Test Reminder (Debug)")
                                    .font(.caption)
                                    .padding(5)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                            .padding(.bottom)
                            #endif
                        }
                    } else {
                        ForEach(appState.reminderManager.getRemindersForWorkPackage(id: workPackage.id)) { reminder in
                            ReminderRow(reminder: reminder)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleReminderTap(reminder)
                                }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                Button(action: {
                    showAddReminder = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Reminder")
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Reminders")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
            .sheet(isPresented: $showAddReminder) {
                ReminderFormView(workPackage: workPackage, isPresented: $showAddReminder)
                    .environmentObject(appState)
            }
            .sheet(item: $reminderToEdit) { reminder in
                ReminderFormView(
                    workPackage: workPackage,
                    isPresented: .constant(true),
                    reminderToEdit: reminder
                )
                .onAppear {
                    NSLog("🔔 Presenting sheet for reminder: \(reminder.id) - WP: \(reminder.workPackageId)")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReminderDeleted"))) { notification in
                    // If this reminder was deleted, dismiss the sheet
                    if let deletedReminderId = notification.object as? UUID, 
                       deletedReminderId == reminder.id {
                        reminderToEdit = nil
                    }
                }
            }
            .onAppear {
                print("\n======== ReminderListView appeared ========")
                print("WorkPackage ID: \(workPackage.id)")
                print("WorkPackage subject: \(workPackage.subject)")
                print("ReminderManager has \(appState.reminderManager.reminders.count) total reminders")
                let wpReminders = appState.reminderManager.getRemindersForWorkPackage(id: workPackage.id)
                print("Found \(wpReminders.count) reminders for this work package")
                
                // Print each work package reminder
                if wpReminders.isEmpty {
                    print("No reminders found for this work package")
                } else {
                    print("Reminders for WorkPackage \(workPackage.id):")
                    for (index, reminder) in wpReminders.enumerated() {
                        print("\t\(index+1). ID: \(reminder.id), Date: \(reminder.reminderDate), Active: \(reminder.isActive)")
                    }
                }
                print("=======================================\n")
            }
        }
    }
    
    private func handleReminderTap(_ reminder: Reminder) {
        NSLog("🔔 Tapped on reminder: \(reminder.id) - WP: \(reminder.workPackageId) - \(reminder.reminderDate)")
        reminderToEdit = reminder
        NSLog("🔔 Set reminderToEdit to: \(String(describing: reminderToEdit?.id))")
    }
}

struct ReminderRow: View {
    var reminder: Reminder
    
    var body: some View {
        HStack {
            Image(systemName: reminder.isActive ? "bell.fill" : "bell.slash")
                .foregroundColor(reminder.isActive ? .blue : .gray)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatDate(reminder.reminderDate))
                        .font(.headline)
                    
                    if !reminder.isActive {
                        Text("(Disabled)")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    // Show overdue indicator if the date is in the past
                    if reminder.isActive && reminder.reminderDate < Date() {
                        Text("Overdue")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                if !reminder.reminderNote.isEmpty {
                    Text(reminder.reminderNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .opacity(reminder.isActive ? 1.0 : 0.6)
    }
    
    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

struct ReminderListView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a stub WorkPackage
        let workPackageSample = WorkPackage(
            id: 123,
            subject: "Sample Work Package",
            description: nil,
            startDate: nil,
            dueDate: nil,
            estimatedTime: nil,
            spentTime: nil,
            percentageDone: nil,
            createdAt: "2025-03-19",
            updatedAt: "2025-03-19",
            lockVersion: 1,
            links: WorkPackageLinks(
                selfLink: Link(href: "http://example.com", title: nil, templated: nil, method: nil),
                project: nil,
                status: nil,
                type: nil,
                priority: nil,
                assignee: nil,
                responsible: nil,
                author: nil,
                activities: nil,
                watchers: nil,
                attachments: nil,
                relations: nil,
                revisions: nil,
                delete: nil,
                update: nil,
                updateImmediately: nil,
                addAttachment: nil,
                addComment: nil,
                addWatcher: nil
            )
        )
        
        return ReminderListView(workPackage: workPackageSample, isPresented: .constant(true))
    }
} 