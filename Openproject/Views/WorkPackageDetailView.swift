//
//  WorkPackageDetailView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
#if os(iOS)
import PDFKit
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
import WebKit
import AVKit
import Combine

// Define HTMLTextView for handling HTML content with special tags
#if os(iOS) || os(macOS)
struct HTMLTextView: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true // Temporarily enable scrolling for diagnosis
        textView.backgroundColor = .clear
        textView.textColor = .label // Use system label color for proper dark mode support
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true // Add this line
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // DEBUG: Print HTML received
        print("--> HTMLTextView updateUIView: Received HTML (length: \(html.count))")
        // Clean HTML content to handle potential issues with OpenProject specific tags
        let cleanedHtml = html.replacingOccurrences(of: "<p class=\"op-uc-p\">", with: "<p>")
        
        // Add CSS to ensure text color adapts to system appearance and proper scaling
        let css = """
            <style>
                body {
                    color: \(UIColor.label.hexString);
                    font-family: -apple-system, system-ui;
                    font-size: 16px;
                    margin: 0;
                    padding: 0;
                    width: 100%;
                }

                /* Ensure images scale to the width of the text view so they
                   don't force the view to grow and appear zoomed */
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }

                /* Ensure tables don't overflow */
                table {
                    max-width: 100%;
                    border-collapse: collapse;
                }

                /* Ensure pre and code blocks don't overflow */
                pre, code {
                    max-width: 100%;
                    overflow-x: auto;
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }

                /* Ensure all block elements respect container width */
                p, div, h1, h2, h3, h4, h5, h6 {
                    max-width: 100%;
                    word-wrap: break-word;
                }
            </style>
        """
        let htmlWithCSS = css + cleanedHtml
        
        if let attributedString = try? NSAttributedString(
            data: Data(htmlWithCSS.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            uiView.attributedText = attributedString
            print("--> HTMLTextView updateUIView: Set attributed string.") // DEBUG
        } else {
            uiView.text = cleanedHtml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            print("--> HTMLTextView updateUIView: Set plain text fallback.") // DEBUG
        }
        
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        uiView.invalidateIntrinsicContentSize()
    }
}
#endif

// Models are already accessible as they are in the same module

struct WorkPackageDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var appState: AppState
    
    // Make this a state variable
    @State private var workPackage: WorkPackage
    
    // All state variables consolidated
    @State private var description: String = ""
    @State private var showEditDescription: Bool = false
    @State private var showAddComment: Bool = false
    @State private var showingTimeLogging: Bool = false
    @State private var showingAddAttachment: Bool = false
    @State private var showingAttachments: Bool = false
    @State private var attachments: [Attachment] = []
    @State private var isAttachmentsChecked = false
    @State private var activities: [Activity] = []
    @State private var isActivitiesSectionExpanded: Bool = false
    @State private var commentText: String = ""
    @State private var refreshID = UUID()
    
    // Basic state for the view
    @State private var isLoading: Bool = false
    @State private var isEditing: Bool = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var types: [WorkPackageType] = []
    @State private var statuses: [WorkPackageStatus] = []
    @State private var priorities: [WorkPackagePriority] = []
    @State private var updatedSubject: String = ""
    @State private var updatedDescription: String = ""
    @State private var selectedStatusId: Int?
    @State private var selectedTypeId: Int?
    @State private var selectedPriorityId: Int?
    @State private var selectedAssigneeId: Int?
    @State private var selectedAssigneeName: String? // Add state for assignee name
    @State private var showingAssigneeSelection = false
    @State private var showingStatusSelection = false
    @State private var showingPrioritySelection = false
    
    // Constructor
    init(workPackage: WorkPackage) {
        self._workPackage = State(initialValue: workPackage)
        self._description = State(initialValue: workPackage.description?.raw ?? "")
    }
    
    // Alternative constructor that takes a workPackageId
    init(workPackageId: Int) {
        // Create a minimal WorkPackage until the real one is loaded
        let placeholderWorkPackage = WorkPackage(
            id: workPackageId,
            subject: "Loading...",
            description: nil,
            startDate: nil,
            dueDate: nil,
            estimatedTime: nil,
            spentTime: nil,
            percentageDone: 0,
            createdAt: "",
            updatedAt: "",
            lockVersion: 0,
            links: WorkPackageLinks(
                selfLink: Link(href: "", title: nil, templated: nil, method: nil),
                project: nil as Link?,
                status: nil as Link?,
                type: nil as Link?,
                priority: nil as Link?,
                assignee: nil as Link?,
                responsible: nil as Link?,
                author: nil as Link?,
                activities: nil as Link?,
                watchers: nil as Link?,
                attachments: nil as Link?,
                relations: nil as Link?,
                revisions: nil as Link?,
                delete: nil as Link?,
                update: nil as Link?,
                updateImmediately: nil as Link?,
                addAttachment: nil as Link?,
                addComment: nil as Link?,
                addWatcher: nil as Link?
            )
        )
        
        self._workPackage = State(initialValue: placeholderWorkPackage)
    }
    
    // Extract IDs from links
    private var typeId: Int? {
        guard let typeLink = workPackage.links.type,
              let href = typeLink.href else { return nil }
        return extractIdFromHref(href)
    }
    
    private var statusId: Int? {
        guard let statusLink = workPackage.links.status?.href else { return nil }
        return extractIdFromHref(statusLink)
    }
    
    private var priorityId: Int? {
        guard let priorityLink = workPackage.links.priority?.href else { return nil }
        return extractIdFromHref(priorityLink)
    }
    
    private var assigneeId: Int? {
        guard let assigneeLink = workPackage.links.assignee?.href else { return nil }
        return extractIdFromHref(assigneeLink)
    }
    
    private func extractIdFromHref(_ href: String) -> Int? {
        let components = href.split(separator: "/")
        if let last = components.last, let id = Int(last) {
            return id
        }
        return nil
    }
    
    // Helper to find types, statuses, and priorities by ID
    private var type: WorkPackageType? {
        guard let id = typeId else { return nil }
        return types.first { $0.id == id }
    }
    
    private var status: WorkPackageStatus? {
        guard let id = statusId else { return nil }
        return statuses.first { $0.id == id }
    }
    
    private var priority: WorkPackagePriority? {
        guard let id = priorityId else { return nil }
        return priorities.first { $0.id == id }
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading) {
            Text("Description")
                .font(.headline)
                .padding(.bottom, 8)
            
            if isEditing {
                TextEditor(text: $updatedDescription)
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.bottom, 8)
            } else if let description = workPackage.description {
                HTMLTextView(html: description.html)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading) // User's recent change here
                    .id(workPackage.updatedAt)
                    .onAppear {
                        #if DEBUG
                        print("--> WorkPackageDetailView Body: Rendering HTMLTextView - HTML: \(description.html), UpdatedAt: \(workPackage.updatedAt)")
                        #endif
                    }
            } else {
                Text("No description")
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // Header with navigation title and edit button
                HStack {
                    if isEditing {
                        TextField("Subject", text: $updatedSubject)
                            .font(.title)
                            .bold()
                            .padding(.bottom, 8)
                    } else {
                        Text(workPackage.subject)
                            .font(.title)
                            .bold()
                            .padding(.bottom, 8)
                    }
                    
                    Spacer()
                    
                    if !isEditing && workPackage.links.update != nil {
                        Button(action: {
                            startEditing()
                        }) {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // ID, Type and Status
                HStack {
                    Text("#\(workPackage.id)")
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    if isEditing {
                        // Type picker
                        if !types.isEmpty {
                            Picker("Type", selection: $selectedTypeId) {
                                ForEach(types) { type in
                                    Text(type.name).tag(type.id as Int?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        // Status picker
                        if !statuses.isEmpty {
                            Button(action: {
                                showingStatusSelection = true
                            }) {
                                HStack {
                                    Text(statuses.first(where: { $0.id == selectedStatusId })?.name ?? "Select Status")
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                        }
                    } else {
                        // Display type 
                        if let typeInfo = type {
                            Text(typeInfo.name)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: typeInfo.color) ?? .blue.opacity(0.2))
                                .cornerRadius(12)
                        }
                        
                        // Display status
                        if let statusInfo = status {
                            Text(statusInfo.name)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: statusInfo.color) ?? .gray.opacity(0.2))
                                .cornerRadius(12)
                        } else {
                            Text(workPackage.links.status?.title ?? "Unknown Status")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
                
                // Priority section
                if let priorityInfo = priority {
                    HStack {
                        Text("Priority:")
                            .foregroundColor(.secondary)
                        
                        if isEditing {
                            Button(action: {
                                showingPrioritySelection = true
                            }) {
                                HStack {
                                    Text(priorities.first(where: { $0.id == selectedPriorityId })?.name ?? "Select Priority")
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            
                            // Add a save button after selections
                            Button(action: saveChanges) {
                                Text("Save Changes")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 12)
                        } else {
                            Text(priorityInfo.name)
                                .foregroundColor(priorityInfo.color != nil ? Color(hex: priorityInfo.color!) : .primary)
                        }
                    }
                    .padding(.top, 4)
                }
                
                // Assignee section
                HStack {
                    Text("Assignee:")
                        .foregroundColor(.secondary)
                    
                    if isEditing {
                        Button(action: {
                            showingAssigneeSelection = true
                        }) {
                            Text(workPackage.links.assignee?.title ?? "Unassigned")
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text(workPackage.links.assignee?.title ?? "Unassigned")
                    }
                }
                .padding(.top, 8)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Description
                descriptionSection
                
                // Dates
                if workPackage.startDate != nil || workPackage.dueDate != nil {
                    VStack(alignment: .leading) {
                        Text("Dates")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        HStack {
                            if let startDate = workPackage.startDate {
                                VStack(alignment: .leading) {
                                    Text("Start Date")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatDate(startDate))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if let dueDate = workPackage.dueDate {
                                VStack(alignment: .leading) {
                                    Text("Due Date")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatDate(dueDate))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Time tracking
                if workPackage.estimatedTime != nil || workPackage.spentTime != nil {
                    VStack(alignment: .leading) {
                        Text("Time Tracking")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        HStack {
                            if let estimatedTime = workPackage.estimatedTime {
                                VStack(alignment: .leading) {
                                    Text("Estimated")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(estimatedTime)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if let spentTime = workPackage.spentTime {
                                VStack(alignment: .leading) {
                                    Text("Spent")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(spentTime)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        if let percentageDone = workPackage.percentageDone {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Progress: \(percentageDone)%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ProgressView(value: Float(percentageDone) / 100)
                                    .progressViewStyle(LinearProgressViewStyle())
                            }
                            .padding(.top, 4)
                        }
                        
                        Button(action: {
                            showingTimeLogging = true
                        }) {
                            Label("Log Time", systemImage: "clock")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                } else {
                    Button(action: {
                        showingTimeLogging = true
                    }) {
                        Label("Log Time", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 8)
                }
                
                // Attachments section
                attachmentsSection
                
                // Activities section
                VStack(alignment: .leading) {
                    HStack {
                        Button(action: {
                            withAnimation {
                                isActivitiesSectionExpanded.toggle()
                                if isActivitiesSectionExpanded {
                                    loadActivities()
                                }
                            }
                        }) {
                            HStack {
                                Text("Activities")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Image(systemName: isActivitiesSectionExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if isActivitiesSectionExpanded {
                            Button(action: {
                                loadActivities()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    
                    if isActivitiesSectionExpanded {
                        if activities.isEmpty {
                            VStack {
                                ProgressView()
                                    .padding()
                                Text("Loading activities...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(activities) { activity in
                                        ActivityRow(activity: activity)
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                }
                .padding(.vertical, 8)
                
                // Edit buttons
                if isEditing {
                    HStack {
                        Button(action: cancelEditing) {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                        
                        Button(action: saveChanges) {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 16)
                } else {
                    // Add comment button
                    Button(action: {
                        showAddComment = true
                    }) {
                        Label("Add Comment", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    .padding(.top, 16)
                    
                    // Delete button (if available)
                    if workPackage.links.delete != nil {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete Work Package", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .overlay(
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                }
            }
        )
        .alert(isPresented: Binding<Bool>(
            get: { self.errorMessage != nil },
            set: { if !$0 { self.errorMessage = nil } }
        )) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Work Package"),
                message: Text("Are you sure you want to delete this work package? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteWorkPackage()
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingAssigneeSelection) {
            // Updated callback handling
            UserSelectionView(currentAssignee: assigneeId, onSelect: { selectedUser in
                selectedAssigneeId = selectedUser?.id
                selectedAssigneeName = selectedUser?.name // Store the name
            }, workPackage: workPackage)
        }
        .sheet(isPresented: $showingStatusSelection) {
            StatusSelectionView(currentStatus: statusId, statuses: statuses, onSelect: { statusId in
                print("Selected status ID: \(String(describing: statusId))")
                selectedStatusId = statusId
            })
        }
        .sheet(isPresented: $showingPrioritySelection) {
            PrioritySelectionView(currentPriority: priorityId, priorities: priorities, onSelect: { priorityId in
                print("Selected priority ID: \(String(describing: priorityId))")
                selectedPriorityId = priorityId
            })
        }
        .sheet(isPresented: $showAddComment) {
            CommentView(workPackageId: workPackage.id, workPackage: workPackage, onCommentAdded: { 
                // Refresh the work package data after comment is added
                loadWorkPackageDetails()
                // Also load activities to show the new comment
                loadActivities()
                // Expand the activities section to show the new comment
                isActivitiesSectionExpanded = true
            })
        }
        .sheet(isPresented: $showingTimeLogging) {
            TimeLogView(workPackageId: workPackage.id, onTimeLogged: {
                // Refresh the work package data after time is logged
                loadWorkPackageDetails()
                // Also reload activities
                loadActivities()
            })
        }
        .sheet(isPresented: $showingAttachments) {
            AttachmentsView(workPackageId: workPackage.id, attachments: attachments, onAttachmentDeleted: {
                // Refresh attachments after one is deleted
                loadAttachments()
                loadWorkPackageDetails()
                // Also reload activities
                loadActivities()
            })
        }
        .sheet(isPresented: $showingAddAttachment) {
            AttachmentUploadView(
                workPackageId: workPackage.id,
                addAttachmentLink: workPackage.addAttachmentLink,
                onAttachmentAdded: {
                    loadAttachments()
                }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingAttachmentPreview) {
            if let attachment = previewAttachment {
                AttachmentPreviewView(attachment: attachment, isPresented: $showingAttachmentPreview)
            }
        }
        .onAppear {
            // Initialize the editing values
            updatedSubject = workPackage.subject
            updatedDescription = workPackage.description?.raw ?? ""
            selectedStatusId = statusId
            selectedTypeId = typeId // Initialize type ID as well
            selectedPriorityId = priorityId
            selectedAssigneeId = assigneeId
            selectedAssigneeName = workPackage.links.assignee?.title // Initialize name from link title
            
            loadWorkPackageDetails()
            loadTypes()
            loadStatuses()
            loadPriorities()
            loadAttachments()
        }
        .navigationTitle("Work Package Details")
    }
    
    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Attachments (\(attachments.count))")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    loadAttachments()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            .padding(.bottom, 8)
            
            if !isAttachmentsChecked {
                ProgressView()
                    .padding()
            } else if attachments.isEmpty {
                Text("No attachments")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Display attachments
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(attachments) { attachment in
                        AttachmentRow(
                            attachment: attachment,
                            previewAttachment: $previewAttachment,
                            showingAttachmentPreview: $showingAttachmentPreview,
                            onDelete: {
                                if let index = self.attachments.firstIndex(where: { $0.id == attachment.id }) {
                                    self.attachments.remove(at: index)
                                }
                                loadAttachments()
                            }
                        )
                    }
                }
            }
                
            // Add attachment button
            Button(action: {
                showingAddAttachment = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add attachment")
                }
                .foregroundColor(.blue)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
    
    struct AttachmentRow: View {
        let attachment: Attachment
        @Binding var previewAttachment: Attachment?
        @Binding var showingAttachmentPreview: Bool
        let onDelete: () -> Void
        
        var body: some View {
            HStack {
                // File icon based on content type
                Image(systemName: iconForContentType(attachment.contentType))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundColor(.blue)
                    .padding(.trailing, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.fileName)
                        .font(.body)
                        .lineLimit(1)
                    
                    Text(formatFileSize(attachment.fileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    openAttachment(attachment)
                }) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal, 8)
                
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        
        private func iconForContentType(_ contentType: String) -> String {
            if contentType.starts(with: "image/") {
                return "photo"
            } else if contentType.starts(with: "video/") {
                return "video"
            } else if contentType.starts(with: "audio/") {
                return "music.note"
            } else if contentType.contains("pdf") {
                return "doc.text"
            } else if contentType.contains("word") || contentType.contains("document") {
                return "doc"
            } else if contentType.contains("excel") || contentType.contains("spreadsheet") {
                return "chart.bar.doc.horizontal"
            } else if contentType.contains("presentation") || contentType.contains("powerpoint") {
                return "chart.bar"
            } else if contentType.contains("zip") || contentType.contains("compressed") {
                return "archivebox"
            } else {
                return "doc.fill"
            }
        }
        
        private func formatFileSize(_ sizeInBytes: Int) -> String {
            let byteCountFormatter = ByteCountFormatter()
            byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteCountFormatter.countStyle = .file
            return byteCountFormatter.string(fromByteCount: Int64(sizeInBytes))
        }
        
        private func openAttachment(_ attachment: Attachment) {
            // Display a custom preview instead of directly opening the URL
            previewAttachment = attachment
            showingAttachmentPreview = true
        }
    }
    
    // MARK: - Attachment Preview
    
    @State private var previewAttachment: Attachment?
    @State private var showingAttachmentPreview = false
    
    private var attachmentPreviewSheet: some View {
        Group {
            if let attachment = previewAttachment {
                AttachmentPreviewView(attachment: attachment, isPresented: $showingAttachmentPreview)
            }
        }
    }
    
    struct AttachmentPreviewView: View {
        let attachment: Attachment
        @Binding var isPresented: Bool
        @State private var isLoading = true
        @State private var previewData: Data?
        @State private var error: String?
        @EnvironmentObject var appState: AppState
        
        var body: some View {
            NavigationView {
                ZStack {
                    Color(.systemBackground).edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        if isLoading {
                            ProgressView("Loading attachment...")
                        } else if let error = error {
                            VStack(spacing: 20) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.red)
                                
                                Text("Error loading attachment")
                                    .font(.headline)
                                
                                Text(error)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                        } else {
                            attachmentContentView
                        }
                    }
                    .padding()
                }
                .navigationBarTitle(attachment.fileName, displayMode: .inline)
                .navigationBarItems(
                    leading: Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    },
                    trailing: Button(action: {
                        shareAttachment()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.primary)
                    }
                )
            }
            .onAppear {
                loadAttachmentContent()
            }
        }
        
        private var attachmentContentView: some View {
            Group {
                if let data = previewData {
                    if attachment.contentType.starts(with: "image/") {
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Text("Unable to display image")
                        }
                    } else if attachment.contentType.starts(with: "application/pdf") {
                        #if os(iOS)
                        PDFKitView(data: data)
                        #else
                        Text("PDF preview not available")
                        #endif
                    } else if attachment.contentType.starts(with: "text/") {
                        if let text = String(data: data, encoding: .utf8) {
                            ScrollView {
                                Text(text)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                            }
                        } else {
                            Text("Unable to display text content")
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: iconForContentType(attachment.contentType))
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("\(attachment.fileName)")
                                .font(.headline)
                            
                            Text("File size: \(formatFileSize(attachment.fileSize))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Content type: \(attachment.contentType)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                openExternally()
                            }) {
                                Label("Open with external app", systemImage: "square.and.arrow.up")
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                } else {
                    Text("No preview available")
                }
            }
        }
        
        private func loadAttachmentContent() {
            guard let accessToken = appState.accessToken else {
                isLoading = false
                error = "Invalid attachment URL"
                return
            }
            
            // Handle both absolute and relative URLs properly
            let urlString = attachment.href.hasPrefix("http") 
                ? attachment.href 
                : appState.constructApiUrl(path: attachment.href)
            
            print("Loading attachment from URL: \(urlString)")
            
            guard let url = URL(string: urlString) else {
                isLoading = false
                error = "Invalid attachment URL: \(attachment.href)"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isLoading = false
                    
                    if let error = error {
                        self.error = "Failed to load: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.error = "Invalid server response"
                        return
                    }
                    
                    if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        self.error = "Server error: \(httpResponse.statusCode)"
                        return
                    }
                    
                    guard let data = data else {
                        self.error = "No data received"
                        return
                    }
                    
                    self.previewData = data
                }
            }.resume()
        }
        
        private func shareAttachment() {
            guard let data = previewData else { return }
            
            #if os(iOS)
            let activityVC = UIActivityViewController(
                activityItems: [data],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let controller = windowScene.windows.first?.rootViewController {
                activityVC.popoverPresentationController?.sourceView = controller.view
                controller.present(activityVC, animated: true)
            }
            #endif
        }
        
        private func openExternally() {
            // Handle both absolute and relative URLs properly
            let urlString = attachment.href.hasPrefix("http") 
                ? attachment.href 
                : appState.constructApiUrl(path: attachment.href)
            
            guard let url = URL(string: urlString) else { return }
            
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
        
        private func iconForContentType(_ contentType: String) -> String {
            if contentType.starts(with: "image/") {
                return "photo"
            } else if contentType.starts(with: "video/") {
                return "video"
            } else if contentType.starts(with: "audio/") {
                return "music.note"
            } else if contentType.contains("pdf") {
                return "doc.text"
            } else if contentType.contains("word") || contentType.contains("document") {
                return "doc"
            } else if contentType.contains("excel") || contentType.contains("spreadsheet") {
                return "chart.bar.doc.horizontal"
            } else if contentType.contains("presentation") || contentType.contains("powerpoint") {
                return "chart.bar"
            } else if contentType.contains("zip") || contentType.contains("compressed") {
                return "archivebox"
            } else {
                return "doc.fill"
            }
        }
        
        private func formatFileSize(_ sizeInBytes: Int) -> String {
            let byteCountFormatter = ByteCountFormatter()
            byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteCountFormatter.countStyle = .file
            return byteCountFormatter.string(fromByteCount: Int64(sizeInBytes))
        }
    }
    
    #if os(iOS)
    struct PDFKitView: UIViewRepresentable {
        let data: Data
        
        func makeUIView(context: Context) -> PDFView {
            let pdfView = PDFView()
            pdfView.autoScales = true
            pdfView.displayMode = .singlePage
            pdfView.displayDirection = .horizontal
            return pdfView
        }
        
        func updateUIView(_ uiView: PDFView, context: Context) {
            if let pdfDocument = PDFDocument(data: data) {
                uiView.document = pdfDocument
            }
        }
    }
    #endif
    
    // MARK: - Helper Methods
    
    private func loadWorkPackageDetails() {
        isLoading = true
        
        // Use appState to fetch the work package details
        guard let accessToken = appState.accessToken else {
            errorMessage = "Cannot load work package: No access token"
            isLoading = false
            return
        }
        
        let url = URL(string: "\(appState.apiBaseURL)/work_packages/\(workPackage.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error loading work package: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                // Try to decode the work package
                do {
                    let decoder = JSONDecoder()
                    let fetchedWorkPackage = try decoder.decode(WorkPackage.self, from: data)
                    self.workPackage = fetchedWorkPackage
                } catch {
                    self.errorMessage = "Error decoding work package: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func loadTypes() {
        guard let accessToken = appState.accessToken else { return }
        
        let url = URL(string: "\(appState.apiBaseURL)/types")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading types: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let typeCollection = try JSONDecoder().decode(TypeCollection.self, from: data)
                    self.types = typeCollection.embedded.elements
                } catch {
                    print("Error decoding types: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func loadStatuses() {
        guard let accessToken = appState.accessToken else { return }
        
        let url = URL(string: "\(appState.apiBaseURL)/statuses")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading statuses: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let statusCollection = try JSONDecoder().decode(StatusCollection.self, from: data)
                    self.statuses = statusCollection.embedded.elements
                } catch {
                    print("Error decoding statuses: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func loadPriorities() {
        guard let accessToken = appState.accessToken else { return }
        
        let url = URL(string: "\(appState.apiBaseURL)/priorities")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading priorities: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let priorityCollection = try JSONDecoder().decode(PriorityCollection.self, from: data)
                    self.priorities = priorityCollection.embedded.elements
                } catch {
                    print("Error decoding priorities: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func loadAttachments() {
        guard let accessToken = appState.accessToken,
              let attachmentsLink = workPackage.links.attachments?.href else {
            print("⚠️ Cannot load attachments: missing link or token")
            return
        }
        
        let urlString = appState.constructApiUrl(path: attachmentsLink)
        guard let url = URL(string: urlString) else { 
            print("⚠️ Invalid attachments URL: \(urlString)")
            return 
        }
        
        print("🔍 Loading attachments from URL: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // Mark as checked regardless of result
                self.isAttachmentsChecked = true
                
                if let error = error {
                    print("❌ Error loading attachments: \(error)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response for attachments")
                    return
                }
                
                print("📡 Attachments API HTTP status: \(httpResponse.statusCode)")
                
                guard let data = data else { 
                    print("❌ No data received from attachments API")
                    return 
                }
                
                print("📦 Attachments API data size: \(data.count) bytes")
                
                // Debug the API response
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Attachments API response: \(responseString.prefix(1000))")
                    
                    // Try to parse as JSON for more structured debugging
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("🧩 Attachments API JSON structure: \(json.keys)")
                            
                            if let embedded = json["_embedded"] as? [String: Any],
                               let elements = embedded["elements"] as? [[String: Any]] {
                                print("✅ Found \(elements.count) attachments in the response")
                                
                                // Check the first element's structure
                                if let firstElement = elements.first {
                                    print("🔍 First attachment structure: \(firstElement.keys)")
                                }
                            } else {
                                print("⚠️ Could not find _embedded.elements in attachments response")
                            }
                        }
                    } catch {
                        print("❌ Error parsing attachments response as JSON: \(error)")
                    }
                }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let attachmentCollection = try decoder.decode(AttachmentCollection.self, from: data)
                    self.attachments = attachmentCollection.embedded.elements
                    print("✅ Successfully loaded \(self.attachments.count) attachments")
                } catch {
                    print("❌ Error decoding attachments: \(error)")
                    
                    // Try to help debug the error by checking which fields might be causing issues
                    do {
                        // Try to decode just the container to see what fields exist
                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                        if let embeddedDict = json?["_embedded"] as? [String: Any],
                           let elements = embeddedDict["elements"] as? [[String: Any]] {
                            
                            print("🔍 Attachments raw structure:")
                            for (i, element) in elements.prefix(2).enumerated() {
                                print("  Attachment \(i): Keys = \(element.keys)")
                            }
                        }
                    } catch {
                        print("❌ Secondary parsing error: \(error)")
                    }
                }
            }
        }.resume()
    }
    
    private func loadActivities() {
        isLoading = true
        errorMessage = nil
        
        guard let accessToken = appState.accessToken else {
            isLoading = false
            errorMessage = "No access token available"
            return
        }
        
        // Set token in UserCache to ensure it's available
        print("🔑 Setting token in UserCache from WorkPackageDetailView: \(accessToken.prefix(5))...")
        UserCache.shared.setToken(accessToken)
        
        // Construct the URL for fetching activities
        let baseURL = URL(string: "https://project.anyitthing.com")!
        let activitiesURL = baseURL.appendingPathComponent("/api/v3/work_packages/\(workPackage.id)/activities")
        
        print("🔍 Loading activities from URL: \(activitiesURL.absoluteString)")
        
        var request = URLRequest(url: activitiesURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to load activities: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                // Debug response
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Activities API HTTP status: \(httpResponse.statusCode)")
                }
                
                print("📦 Activities API data size: \(data.count) bytes")
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    let previewLength = min(jsonString.count, 500)
                    let preview = jsonString.prefix(previewLength) + (jsonString.count > previewLength ? "..." : "")
                    print("📄 Activities API response: \(preview)")
                }
                
                do {
                    // First parse as dictionary to examine structure
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🧩 Activities API JSON structure: \(json.keys)")
                        
                        if let embedded = json["_embedded"] as? [String: Any],
                           let elements = embedded["elements"] as? [[String: Any]] {
                            print("✅ Found \(elements.count) activities in the response")
                            
                            // Check the first element's structure
                            if let firstElement = elements.first {
                                print("🔍 First activity structure: \(firstElement.keys)")
                                
                                // Debug links section
                                if let links = firstElement["_links"] as? [String: Any] {
                                    print("📎 Activity links: \(links.keys)")
                                    if let user = links["user"] as? [String: Any] {
                                        print("👤 User link: \(user)")
                                    }
                                }
                            }
                        } else {
                            print("❌ Could not find elements in _embedded")
                        }
                    }
                    
                    // Now try to decode into the model
                    let decoder = JSONDecoder()
                    let activityCollection = try decoder.decode(ActivityCollection.self, from: data)
                    
                    // Sort activities by createdAt descending before assigning
                    let sortedActivities = activityCollection.embedded.elements.sorted { $0.createdAt > $1.createdAt }
                    self.activities = sortedActivities
                    
                    print("✅ Successfully loaded and sorted \(self.activities.count) activities")
                } catch {
                    print("❌ Error decoding activities: \(error)")
                    
                    // Try to examine raw structure for debugging
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let embedded = json["_embedded"] as? [String: Any],
                       let elements = embedded["elements"] as? [[String: Any]] {
                        
                        print("🔍 Activities raw structure:")
                        for (index, element) in elements.prefix(2).enumerated() {
                            print("  Activity \(index): Keys = \(element.keys)")
                        }
                    }
                    
                    self.errorMessage = "Error parsing activities: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func startEditing() {
        // Save the current values to use as defaults
        updatedSubject = workPackage.subject
        updatedDescription = workPackage.description?.raw ?? ""
        
        // Explicitly get the current IDs to initialize the selection state
        selectedStatusId = statusId
        selectedTypeId = typeId
        selectedPriorityId = priorityId
        selectedAssigneeId = assigneeId
        
        print("Starting edit mode with status: \(String(describing: selectedStatusId)), priority: \(String(describing: selectedPriorityId)), assignee: \(String(describing: selectedAssigneeId))")
        isEditing = true
    }
    
    private func cancelEditing() {
        isEditing = false
    }
    
    private func saveChanges() {
        isLoading = true
        
        // Ensure we have an access token
        guard let accessToken = appState.accessToken else {
            errorMessage = "Cannot update work package: No access token available"
            isLoading = false
            return
        }
        
        // Get update link, or construct it directly if not available
        var updateLink: String
        if let providedLink = workPackage.links.update?.href {
            updateLink = providedLink
            print("Using provided update link: \(updateLink)")
        } else {
            // Construct the update URL directly
            updateLink = "/api/v3/work_packages/\(workPackage.id)"
            print("Constructed direct update link: \(updateLink)")
        }
        
        // Print the raw update link for debugging
        print("Raw update link from API: \(updateLink)")
        
        // Remove "/form" from the end of the link if present
        var cleanUpdateLink = updateLink
        if cleanUpdateLink.hasSuffix("/form") {
            cleanUpdateLink = String(cleanUpdateLink.dropLast(5))
            print("Removed '/form' from update link: \(cleanUpdateLink)")
        }
        
        // Ensure we use the proper URL construction
        let url: URL
        if cleanUpdateLink.hasPrefix("http") {
            // It's already a full URL
            url = URL(string: cleanUpdateLink)!
        } else {
            // It's a relative path, use the constructApiUrl method
            url = URL(string: appState.constructApiUrl(path: cleanUpdateLink))!
        }
        
        print("Final update URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Using HTTP method: \(request.httpMethod ?? "UNKNOWN")")
        
        // Create update payload
        var updateData: [String: Any] = [
            "subject": updatedSubject,
            "lockVersion": workPackage.lockVersion
        ]
        
        if !updatedDescription.isEmpty {
            updateData["description"] = ["raw": updatedDescription]
        }
        
        // Add links section for references
        var links: [String: Any] = [:]
        
        if let typeId = selectedTypeId {
            // Handle type link properly - use full URL format if necessary
            let typeHref = "\(appState.apiBaseURL)/types/\(typeId)"
                .replacingOccurrences(of: "//api", with: "/api") // Fix potential double slash
            links["type"] = ["href": typeHref]
        }
        
        if let statusId = selectedStatusId {
            print("Adding status ID \(statusId) to update request")
            // Handle status link properly - use full URL format if necessary
            let statusHref = "\(appState.apiBaseURL)/statuses/\(statusId)"
                .replacingOccurrences(of: "//api", with: "/api") // Fix potential double slash
            links["status"] = ["href": statusHref]
        }
        
        if let priorityId = selectedPriorityId {
            print("Adding priority ID \(priorityId) to update request")
            // Handle priority link properly - use full URL format if necessary
            let priorityHref = "\(appState.apiBaseURL)/priorities/\(priorityId)"
                .replacingOccurrences(of: "//api", with: "/api") // Fix potential double slash
            links["priority"] = ["href": priorityHref]
        }
        
        if let assigneeId = selectedAssigneeId {
            print("Adding assignee ID \(assigneeId) to update request")
            // Handle assignee link properly - use full URL format if necessary
            let assigneeHref = "\(appState.apiBaseURL)/users/\(assigneeId)"
                .replacingOccurrences(of: "//api", with: "/api") // Fix potential double slash
            links["assignee"] = ["href": assigneeHref]
        } else if selectedAssigneeId == nil && !isEditing {
            // Only unassign if explicitly set to nil during editing
            links["assignee"] = NSNull()
        }
        
        if !links.isEmpty {
            print("Adding links to update: \(links)")
            updateData["_links"] = links
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: updateData)
            request.httpBody = jsonData
            
            // Log the request payload for debugging
            if let requestBody = String(data: jsonData, encoding: .utf8) {
                print("Update Request Body: \(requestBody)")
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error updating work package: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = "Invalid response"
                        return
                    }
                    
                    // Print response details for debugging
                    print("Update Response Status: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Update Response Body: \(responseString)")
                    }
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        let newDescription = updatedDescription.isEmpty ? nil : ProjectDescription(format: "markdown", raw: updatedDescription, html: updatedDescription)

                        var tempUpdatedWorkPackage = self.workPackage
                        tempUpdatedWorkPackage.subject = self.updatedSubject
                        tempUpdatedWorkPackage.description = newDescription
                        tempUpdatedWorkPackage.lockVersion += 1
                        tempUpdatedWorkPackage.updatedAt = ISO8601DateFormatter().string(from: Date())
                       
                        // ... update links ...
                        if let statusId = self.selectedStatusId, let status = self.statuses.first(where: { $0.id == statusId }) {
                           tempUpdatedWorkPackage.links.status = Link(href: "/api/v3/statuses/\(statusId)", title: status.name, templated: nil, method: nil)
                        }
                        if let priorityId = self.selectedPriorityId, let priority = self.priorities.first(where: { $0.id == priorityId }) {
                           tempUpdatedWorkPackage.links.priority = Link(href: "/api/v3/priorities/\(priorityId)", title: priority.name, templated: nil, method: nil)
                        }
                        let assigneeTitle = self.selectedAssigneeName ?? "Unassigned"
                        tempUpdatedWorkPackage.links.assignee = self.selectedAssigneeId != nil ? Link(href: "/api/v3/users/\(self.selectedAssigneeId!)", title: assigneeTitle, templated: nil, method: nil) : nil

                        // DEBUG: Print the work package state just before assigning
                        print("--> WorkPackageDetailView saveChanges: Updating state with - Desc HTML: \(tempUpdatedWorkPackage.description?.html ?? "nil"), UpdatedAt: \(tempUpdatedWorkPackage.updatedAt)")
                        
                        // --- Assign the locally updated object back to the state --- 
                        self.workPackage = tempUpdatedWorkPackage // Trigger UI update with local changes
                        
                        self.isEditing = false // Switch back to display mode
                        print("Work package updated locally and UI switched to display mode.")
                        
                        // Optionally reload from server for definitive state, uncomment if needed:
                        // self.loadWorkPackageDetails()
                    } else {
                        // Handle non-2xx responses
                        // Corrected: Use APIErrorResponse
                        if let data = data, let errorBody = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                            // Extract detailed error message if available
                            var detailedMessage = errorBody.message ?? "Unknown error updating work package."
                            // Note: APIErrorResponse doesn't have a 'details' field based on its definition.
                            // If the API *does* return details, the APIErrorResponse struct needs updating.
                            // For now, we just use the main message.
                            self.errorMessage = detailedMessage
                            print("Error Details: \(detailedMessage)")
                        } else {
                            self.errorMessage = "Error updating work package (Status: \(httpResponse.statusCode))"
                        }
                    }
                }
            }.resume()
            
        } catch {
            isLoading = false
            errorMessage = "Error encoding update data: \(error.localizedDescription)"
        }
    }
    
    private func deleteWorkPackage() {
        isLoading = true
        
        guard let accessToken = appState.accessToken,
              let deleteLink = workPackage.links.delete?.href,
              let url = URL(string: appState.constructApiUrl(path: deleteLink)) else {
            errorMessage = "Cannot delete work package: Missing required information"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error deleting work package: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Navigate back to the previous screen
                    NotificationCenter.default.post(name: NSNotification.Name("WorkPackageDeleted"), object: nil)
                } else {
                    self.errorMessage = "Error deleting work package: HTTP \(httpResponse.statusCode)"
                }
            }
        }.resume()
    }
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        
        return outputFormatter.string(from: date)
    }
    
    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

// User selection view for assignee
struct UserSelectionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingMentionsList = false
    @State private var cursorPosition = 0
    @State private var mentionQuery = ""
    @State private var mentionStartIndex: Int = 0
    let currentAssignee: Int?
    let onSelect: (User?) -> Void // Changed signature to return User?
    let workPackage: WorkPackage
    
    var body: some View {
        NavigationView {
            List {
                Button {
                    onSelect(nil) // Pass nil for unassigned
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    HStack {
                        Text("Unassigned")
                            .foregroundColor(.primary)
                        Spacer()
                        if currentAssignee == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ForEach(users) { user in
                    Button {
                        onSelect(user) // Pass the selected User object
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Text(user.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if currentAssignee == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Assignee")
            .overlay(Group {
                if isLoading {
                    ProgressView()
                }
            })
            .alert(isPresented: Binding<Bool>(
                get: { self.errorMessage != nil },
                set: { if !$0 { self.errorMessage = nil } }
            )) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "Unknown error"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadUsers()
            }
        }
    }
    
    private func loadUsers() {
        isLoading = true
        
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoading = false
            return
        }
        
        // First try to get project members since they often have permissions on the work package
        if let projectId = extractProjectId() {
            loadProjectMembers(projectId: projectId)
        } else {
            // If we can't get the project ID, try with available assignees
            tryAvailableAssignees()
        }
    }
    
    private func extractProjectId() -> Int? {
        // Try to extract project ID from work package links
        if let projectLink = workPackage.links.project?.href,
           let projectIdStr = projectLink.components(separatedBy: "/").last,
           let projectId = Int(projectIdStr) {
            return projectId
        }
        return nil
    }
    
    private func loadProjectMembers(projectId: Int) {
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoading = false
            return
        }
        
        let projectMembersURL = "\(appState.apiBaseURL)/projects/\(projectId)/members"
        
        guard let url = URL(string: projectMembersURL) else {
            errorMessage = "Invalid URL format"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Fetching project \(projectId) members for assignees")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Check for response errors
            if let httpResponse = response as? HTTPURLResponse {
                // Check for permission errors
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    print("Permission error accessing project members endpoint: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.tryAvailableAssignees()
                    }
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                    // Check if response contains error before trying to parse
                    if let jsonString = String(data: data, encoding: .utf8),
                       jsonString.contains("errorIdentifier") {
                        print("API returned error response for project members, trying next approach")
                        DispatchQueue.main.async {
                            self.tryAvailableAssignees()
                        }
                        return
                    }
                    
                    self.extractUsersFromMembers(data: data)
                } else {
                    DispatchQueue.main.async {
                        self.tryAvailableAssignees()
                    }
                }
            } else {
                // If failed, try the available assignees endpoint
                DispatchQueue.main.async {
                    self.tryAvailableAssignees()
                }
            }
        }.resume()
    }
    
    private func extractUsersFromMembers(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let embedded = json["_embedded"] as? [String: Any],
               let elements = embedded["elements"] as? [[String: Any]] {
                
                var memberUsers: [User] = []
                var seenUserIds = Set<Int>()
                
                for element in elements {
                    if let links = element["_links"] as? [String: Any],
                       let principal = links["principal"] as? [String: Any],
                       let href = principal["href"] as? String,
                       let title = principal["title"] as? String {
                        
                        if let userId = href.components(separatedBy: "/").last, let id = Int(userId) {
                            // Avoid duplicates
                            if !seenUserIds.contains(id) {
                                seenUserIds.insert(id)
                                
                                let user = User(
                                    id: id,
                                    name: title,
                                    firstName: "",
                                    lastName: "",
                                    email: nil,
                                    avatar: nil,
                                    status: "",
                                    language: "",
                                    admin: nil,
                                    createdAt: "",
                                    updatedAt: ""
                                )
                                memberUsers.append(user)
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    if !memberUsers.isEmpty {
                        self.users = memberUsers
                        print("Extracted \(memberUsers.count) users from project members")
                        self.isLoading = false
                    } else {
                        // Try available assignees endpoint as fallback
                        self.tryAvailableAssignees()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.tryAvailableAssignees()
                }
            }
        } catch {
            print("Error parsing project members: \(error)")
            DispatchQueue.main.async {
                self.tryAvailableAssignees()
            }
        }
    }
    
    private func tryAvailableAssignees() {
        // Try to get assignable users for this work package
        let workPackageId = workPackage.id
        var urlComponents = URLComponents(string: "\(appState.apiBaseURL)/work_packages/\(workPackageId)/available_assignees")!
        
        guard let url = urlComponents.url,
              let accessToken = appState.accessToken else {
            DispatchQueue.main.async {
                self.addCurrentUserAsFallback()
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Trying to fetch available assignees for work package \(workPackageId)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // If we received any data, check it for error messages before anything else
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                // Early detection of error responses
                if responseString.contains("errorIdentifier") || responseString.contains("MissingPermission") {
                    print("Permission error detected in response body")
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                    return
                }
            }
            
            // First check for HTTP errors that indicate permission issues
            if let httpResponse = response as? HTTPURLResponse {
                // Handle permission errors without trying to decode the response
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    print("Permission error accessing available_assignees endpoint: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                    return
                }
                
                // Only try to decode if we got a successful response
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                    // Check if the response contains an error message before attempting to decode
                    if let jsonString = String(data: data, encoding: .utf8),
                       jsonString.contains("errorIdentifier") {
                        print("API returned error response, using fallback")
                        DispatchQueue.main.async {
                            self.addCurrentUserAsFallback()
                        }
                        return
                    }
                    
                    print("Successfully got assignees response")
                    self.processUserData(data: data)
                } else {
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                }
            } else {
                // If all else fails, fall back to using just the current user
                DispatchQueue.main.async {
                    self.addCurrentUserAsFallback()
                }
            }
        }.resume()
    }
    
    private func processUserData(data: Data) {
        // Check for error response before dispatching to main thread
        if let jsonString = String(data: data, encoding: .utf8),
           jsonString.contains("errorIdentifier") || jsonString.contains("MissingPermission") {
            print("Detected API permission error, using current user fallback")
            DispatchQueue.main.async {
                self.addCurrentUserAsFallback()
            }
            return
        }
        
        DispatchQueue.main.async {
            do {
                // Try to detect error responses before decoding
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["_type"] as? String == "Error" {
                    print("Received error response from API, using fallback")
                    self.addCurrentUserAsFallback()
                    return
                }
                
                // Try standard decode 
                let decoder = JSONDecoder()
                let userCollection = try decoder.decode(UserCollection.self, from: data)
                self.users = userCollection.embedded.elements
                print("Successfully loaded \(self.users.count) users for assignees")
                self.isLoading = false
            } catch {
                print("Error decoding users response (likely a non-standard format): \(error)")
                
                // Attempt to parse manually if standard decode fails
                self.parseManually(data: data)
            }
        }
    }
    
    private func parseManually(data: Data) {
        do {
            // First check if this is an error response
            if let jsonString = String(data: data, encoding: .utf8),
               jsonString.contains("errorIdentifier") {
                print("Detected error response during manual parsing, using fallback")
                self.addCurrentUserAsFallback()
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if this is an error response before continuing
                if let type = json["_type"] as? String, type == "Error" {
                    print("Error response detected in manual parsing: \(json["message"] as? String ?? "Unknown error")")
                    self.addCurrentUserAsFallback()
                    return
                }
                
                // Check if this is a single user response
                if let id = json["id"] as? Int,
                   let name = json["name"] as? String {
                    
                    // Create a single user
                    let user = User(
                        id: id,
                        name: name,
                        firstName: json["firstName"] as? String ?? "",
                        lastName: json["lastName"] as? String ?? "",
                        email: json["email"] as? String,
                        avatar: json["avatar"] as? String,
                        status: json["status"] as? String ?? "",
                        language: json["language"] as? String ?? "",
                        admin: json["admin"] as? Bool,
                        createdAt: json["createdAt"] as? String ?? "",
                        updatedAt: json["updatedAt"] as? String ?? ""
                    )
                    
                    self.users = [user]
                    print("Loaded single user for assignee: \(user.name)")
                } 
                // Check if it's embedded in _embedded.elements
                else if let embedded = json["_embedded"] as? [String: Any],
                        let elements = embedded["elements"] as? [[String: Any]] {
                    // Process elements array
                    processElementsArray(elements)
                }
                // Check if it's a direct array
                else if let elements = json["elements"] as? [[String: Any]] {
                    // Process elements array
                    processElementsArray(elements)
                }
                // If we couldn't parse anything, fall back
                else {
                    self.addCurrentUserAsFallback()
                }
            } else {
                self.addCurrentUserAsFallback()
            }
        } catch {
            print("Failed manual parsing: \(error)")
            self.addCurrentUserAsFallback()
        }
        
        self.isLoading = false
    }
    
    private func processElementsArray(_ elements: [[String: Any]]) {
        var parsedUsers: [User] = []
        var seenUserIds = Set<Int>()
        
        for element in elements {
            if let id = element["id"] as? Int,
               let name = element["name"] as? String {
                // Avoid duplicates
                if !seenUserIds.contains(id) {
                    seenUserIds.insert(id)
                    
                    let user = User(
                        id: id,
                        name: name,
                        firstName: element["firstName"] as? String ?? "",
                        lastName: element["lastName"] as? String ?? "",
                        email: element["email"] as? String,
                        avatar: element["avatar"] as? String,
                        status: element["status"] as? String ?? "",
                        language: element["language"] as? String ?? "",
                        admin: element["admin"] as? Bool,
                        createdAt: element["createdAt"] as? String ?? "",
                        updatedAt: element["updatedAt"] as? String ?? ""
                    )
                    parsedUsers.append(user)
                }
            }
        }
        
        if !parsedUsers.isEmpty {
            self.users = parsedUsers
            print("Manually parsed \(parsedUsers.count) users for assignees")
        } else {
            self.addCurrentUserAsFallback()
        }
    }
    
    private func addCurrentUserAsFallback() {
        // Always make sure to add the current user
        if let currentUser = appState.user {
            users = [currentUser]
            print("Using current user as fallback")
        }
        isLoading = false
    }
}

// Comment view
struct CommentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @State private var commentText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var users: [User] = []
    @State private var isLoadingUsers = false
    @State private var showingMentionsList = false
    @State private var cursorPosition = 0
    @State private var mentionQuery = ""
    @State private var mentionStartIndex: Int = 0
    let workPackageId: Int
    let workPackage: WorkPackage
    let onCommentAdded: () -> Void
    
    var filteredUsers: [User] {
        if mentionQuery.isEmpty {
            return users
        } else {
            return users.filter { user in
                user.name.lowercased().contains(mentionQuery.lowercased())
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 16) {
                    CustomTextEditor(text: $commentText, cursorPosition: $cursorPosition, onMentionTriggered: { position, query, startIdx in
                        self.cursorPosition = position
                        self.mentionQuery = query
                        self.mentionStartIndex = startIdx
                        self.showingMentionsList = true
                        if self.users.isEmpty {
                            loadUsers()
                        }
                    })
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding()
                    
                    HStack {
                        Text("Use @ to mention users")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if showingMentionsList {
                            Text("Typing: @\(mentionQuery)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    Button(action: submitComment) {
                        Text("Submit Comment")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(commentText.isEmpty || isSubmitting)
                    .padding(.horizontal)
                    
                    Spacer()
                }
                
                if showingMentionsList && !isLoadingUsers {
                    VStack {
                        HStack {
                            Text("Select User to Mention")
                                .font(.headline)
                                .padding()
                            
                            Spacer()
                            
                            Button(action: {
                                showingMentionsList = false
                            }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        }
                        
                        Divider()
                        
                        if filteredUsers.isEmpty {
                            Text("No users found")
                                .padding()
                        } else {
                            List {
                                ForEach(filteredUsers) { user in
                                    Button(action: {
                                        insertMention(user)
                                        showingMentionsList = false
                                    }) {
                                        HStack {
                                            Text(user.name)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Circle()
                                                .fill(Color.blue.opacity(0.2))
                                                .frame(width: 30, height: 30)
                                                .overlay(
                                                    Text(String(user.name.prefix(1)))
                                                        .foregroundColor(.blue)
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding()
                    .transition(.opacity)
                }
            }
            .navigationTitle("Add Comment")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .overlay(Group {
                if isSubmitting || isLoadingUsers {
                    ProgressView()
                }
            })
            .alert(isPresented: Binding<Bool>(
                get: { self.errorMessage != nil },
                set: { if !$0 { self.errorMessage = nil } }
            )) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "Unknown error"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func loadUsers() {
        isLoadingUsers = true
        
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoadingUsers = false
            return
        }
        
        // First try to get project members since they often have permissions on the work package
        if let projectId = extractProjectId() {
            loadProjectMembers(projectId: projectId)
        } else {
            // If we can't get the project ID, try with available assignees
            tryAvailableAssignees()
        }
    }
    
    private func extractProjectId() -> Int? {
        // Try to extract project ID from work package links
        if let projectLink = workPackage.links.project?.href,
           let projectIdStr = projectLink.components(separatedBy: "/").last,
           let projectId = Int(projectIdStr) {
            return projectId
        }
        return nil
    }
    
    private func loadProjectMembers(projectId: Int) {
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoadingUsers = false
            return
        }
        
        let projectMembersURL = "\(appState.apiBaseURL)/projects/\(projectId)/members"
        
        guard let url = URL(string: projectMembersURL) else {
            errorMessage = "Invalid URL format"
            isLoadingUsers = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Fetching project \(projectId) members for mentions")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Check for response errors
            if let httpResponse = response as? HTTPURLResponse {
                // Check for permission errors
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    print("Permission error accessing project members endpoint: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.tryAvailableAssignees()
                    }
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                    // Check if response contains error before trying to parse
                    if let jsonString = String(data: data, encoding: .utf8),
                       jsonString.contains("errorIdentifier") {
                        print("API returned error response for project members, trying next approach")
                        DispatchQueue.main.async {
                            self.tryAvailableAssignees()
                        }
                        return
                    }
                    
                    self.extractUsersFromMembers(data: data)
                } else {
                    DispatchQueue.main.async {
                        self.tryAvailableAssignees()
                    }
                }
            } else {
                // If failed, try the available assignees endpoint
                DispatchQueue.main.async {
                    self.tryAvailableAssignees()
                }
            }
        }.resume()
    }
    
    private func extractUsersFromMembers(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let embedded = json["_embedded"] as? [String: Any],
               let elements = embedded["elements"] as? [[String: Any]] {
                
                var memberUsers: [User] = []
                var seenUserIds = Set<Int>()
                
                for element in elements {
                    if let links = element["_links"] as? [String: Any],
                       let principal = links["principal"] as? [String: Any],
                       let href = principal["href"] as? String,
                       let title = principal["title"] as? String {
                        
                        if let userId = href.components(separatedBy: "/").last, let id = Int(userId) {
                            // Avoid duplicates
                            if !seenUserIds.contains(id) {
                                seenUserIds.insert(id)
                                
                                let user = User(
                                    id: id,
                                    name: title,
                                    firstName: "",
                                    lastName: "",
                                    email: nil,
                                    avatar: nil,
                                    status: "",
                                    language: "",
                                    admin: nil,
                                    createdAt: "",
                                    updatedAt: ""
                                )
                                memberUsers.append(user)
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    if !memberUsers.isEmpty {
                        self.users = memberUsers
                        print("Extracted \(memberUsers.count) users from project members")
                        self.isLoadingUsers = false
                    } else {
                        // Try available assignees endpoint as fallback
                        self.tryAvailableAssignees()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.tryAvailableAssignees()
                }
            }
        } catch {
            print("Error parsing project members: \(error)")
            DispatchQueue.main.async {
                self.tryAvailableAssignees()
            }
        }
    }
    
    private func tryAvailableAssignees() {
        // Try to get assignable users for this work package
        var urlComponents = URLComponents(string: "\(appState.apiBaseURL)/work_packages/\(workPackageId)/available_assignees")!
        
        guard let url = urlComponents.url,
              let accessToken = appState.accessToken else {
            DispatchQueue.main.async {
                self.addCurrentUserAsFallback()
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Trying to fetch available assignees for work package \(workPackageId)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // If we received any data, check it for error messages before anything else
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                // Early detection of error responses
                if responseString.contains("errorIdentifier") || responseString.contains("MissingPermission") {
                    print("Permission error detected in response body")
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                    return
                }
            }
            
            // First check for HTTP errors that indicate permission issues
            if let httpResponse = response as? HTTPURLResponse {
                // Handle permission errors without trying to decode the response
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    print("Permission error accessing available_assignees endpoint: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                    return
                }
                
                // Only try to decode if we got a successful response
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                    // Check if the response contains an error message before attempting to decode
                    if let jsonString = String(data: data, encoding: .utf8),
                       jsonString.contains("errorIdentifier") {
                        print("API returned error response, using fallback")
                        DispatchQueue.main.async {
                            self.addCurrentUserAsFallback()
                        }
                        return
                    }
                    
                    print("Successfully got assignees response")
                    self.processUserData(data: data)
                } else {
                    DispatchQueue.main.async {
                        self.addCurrentUserAsFallback()
                    }
                }
            } else {
                // If all else fails, fall back to using just the current user
                DispatchQueue.main.async {
                    self.addCurrentUserAsFallback()
                }
            }
        }.resume()
    }
    
    private func processUserData(data: Data) {
        // Check for error response before dispatching to main thread
        if let jsonString = String(data: data, encoding: .utf8),
           jsonString.contains("errorIdentifier") || jsonString.contains("MissingPermission") {
            print("Detected API permission error, using current user fallback")
            DispatchQueue.main.async {
                self.addCurrentUserAsFallback()
            }
            return
        }
        
        DispatchQueue.main.async {
            do {
                // Try to detect error responses before decoding
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["_type"] as? String == "Error" {
                    print("Received error response from API, using fallback")
                    self.addCurrentUserAsFallback()
                    return
                }
                
                // Try standard decode 
                let decoder = JSONDecoder()
                let userCollection = try decoder.decode(UserCollection.self, from: data)
                self.users = userCollection.embedded.elements
                print("Successfully loaded \(self.users.count) users for mentions")
                self.isLoadingUsers = false
            } catch {
                print("Error decoding users response (likely a non-standard format): \(error)")
                
                // Attempt to parse manually if standard decode fails
                self.parseManually(data: data)
            }
        }
    }
    
    private func parseManually(data: Data) {
        do {
            // First check if this is an error response
            if let jsonString = String(data: data, encoding: .utf8),
               jsonString.contains("errorIdentifier") {
                print("Detected error response during manual parsing, using fallback")
                self.addCurrentUserAsFallback()
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if this is an error response before continuing
                if let type = json["_type"] as? String, type == "Error" {
                    print("Error response detected in manual parsing: \(json["message"] as? String ?? "Unknown error")")
                    self.addCurrentUserAsFallback()
                    return
                }
                
                // Check if this is a single user response
                if let id = json["id"] as? Int,
                   let name = json["name"] as? String {
                    
                    // Create a single user
                    let user = User(
                        id: id,
                        name: name,
                        firstName: json["firstName"] as? String ?? "",
                        lastName: json["lastName"] as? String ?? "",
                        email: json["email"] as? String,
                        avatar: json["avatar"] as? String,
                        status: json["status"] as? String ?? "",
                        language: json["language"] as? String ?? "",
                        admin: json["admin"] as? Bool,
                        createdAt: json["createdAt"] as? String ?? "",
                        updatedAt: json["updatedAt"] as? String ?? ""
                    )
                    
                    self.users = [user]
                    print("Loaded single user for mention: \(user.name)")
                } 
                // Check if it's embedded in _embedded.elements
                else if let embedded = json["_embedded"] as? [String: Any],
                        let elements = embedded["elements"] as? [[String: Any]] {
                    // Process elements array
                    processElementsArray(elements)
                }
                // Check if it's a direct array
                else if let elements = json["elements"] as? [[String: Any]] {
                    // Process elements array
                    processElementsArray(elements)
                }
                // If we couldn't parse anything, fall back
                else {
                    self.addCurrentUserAsFallback()
                }
            } else {
                self.addCurrentUserAsFallback()
            }
        } catch {
            print("Failed manual parsing: \(error)")
            self.addCurrentUserAsFallback()
        }
        
        self.isLoadingUsers = false
    }
    
    private func processElementsArray(_ elements: [[String: Any]]) {
        var parsedUsers: [User] = []
        var seenUserIds = Set<Int>()
        
        for element in elements {
            if let id = element["id"] as? Int,
               let name = element["name"] as? String {
                // Avoid duplicates
                if !seenUserIds.contains(id) {
                    seenUserIds.insert(id)
                    
                    let user = User(
                        id: id,
                        name: name,
                        firstName: element["firstName"] as? String ?? "",
                        lastName: element["lastName"] as? String ?? "",
                        email: element["email"] as? String,
                        avatar: element["avatar"] as? String,
                        status: element["status"] as? String ?? "",
                        language: element["language"] as? String ?? "",
                        admin: element["admin"] as? Bool,
                        createdAt: element["createdAt"] as? String ?? "",
                        updatedAt: element["updatedAt"] as? String ?? ""
                    )
                    parsedUsers.append(user)
                }
            }
        }
        
        if !parsedUsers.isEmpty {
            self.users = parsedUsers
            print("Manually parsed \(parsedUsers.count) users for mentions")
        } else {
            self.addCurrentUserAsFallback()
        }
    }
    
    private func addCurrentUserAsFallback() {
        // Always make sure to add the current user
        if let currentUser = appState.user {
            users = [currentUser]
            print("Using current user as fallback")
        }
        isLoadingUsers = false
    }
    
    private func insertMention(_ user: User) {
        // Calculate the true position in the string from the start of the @ character
        let atIndex = mentionStartIndex
        
        if atIndex >= 0 && atIndex < commentText.count {
            // Get start and end indexes for the mention query
            let textIndex = commentText.index(commentText.startIndex, offsetBy: atIndex)
            let queryStartIndex = commentText.index(after: textIndex)
            let queryLength = mentionQuery.count
            
            if queryLength > 0 {
                let queryEndIndex = commentText.index(queryStartIndex, offsetBy: queryLength)
                
                // Replace @query with @username
                let mentionText = "@\(user.name) " // Add space after the mention
                let beforeMention = commentText[..<textIndex]
                let afterMention = commentText[queryEndIndex...]
                commentText = String(beforeMention) + mentionText + String(afterMention)
            } else {
                // Just insert the username if there's no query
                let mentionText = "@\(user.name) " // Add space after the mention
                let beforeMention = commentText[..<textIndex]
                let afterText = commentText[textIndex...]
                commentText = String(beforeMention) + mentionText + String(afterText.dropFirst()) // Drop the @ character
            }
        }
        
        // Reset mention state
        mentionQuery = ""
    }
    
    private func submitComment() {
        isSubmitting = true
        
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isSubmitting = false
            return
        }
        
        let url = URL(string: "\(appState.apiBaseURL)/work_packages/\(workPackageId)/activities")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Submitting comment with text: \(commentText)")
        
        // OpenProject API supports mentions via plain text @username format
        let commentData = ["comment": ["raw": commentText]]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: commentData)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    
                    if let error = error {
                        print("Error submitting comment: \(error)")
                        errorMessage = "Error submitting comment: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        errorMessage = "Invalid response"
                        return
                    }
                    
                    print("Comment submission response code: \(httpResponse.statusCode)")
                    
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Comment response: \(responseString)")
                    }
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        print("Comment submitted successfully")
                        onCommentAdded()
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        print("Failed to submit comment: HTTP \(httpResponse.statusCode)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            errorMessage = "Error submitting comment: HTTP \(httpResponse.statusCode)\n\(responseString)"
                        } else {
                            errorMessage = "Error submitting comment: HTTP \(httpResponse.statusCode)"
                        }
                    }
                }
            }.resume()
            
        } catch {
            isSubmitting = false
            print("Error encoding comment: \(error)")
            errorMessage = "Error encoding comment: \(error.localizedDescription)"
        }
    }
}

// Custom TextEditor that detects @ mentions
struct CustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var onMentionTriggered: (Int, String, Int) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = .label // Use system label color for proper dark mode support
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextEditor
        private var atSignIndex: Int = -1
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            
            // Check for @ mentions
            if let selectedRange = textView.selectedTextRange {
                // The offset method returns a non-optional Int
                let cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
                parent.cursorPosition = cursorPosition
                
                // Look for @ before cursor
                if cursorPosition > 0 {
                    let text = textView.text as NSString
                    let startSearchIndex = max(0, cursorPosition - 50) // Search 50 chars back
                    let searchText = text.substring(with: NSRange(location: startSearchIndex, length: cursorPosition - startSearchIndex))
                    
                    // Find the last @ that's not inside a word
                    if let lastAtSign = searchText.range(of: "@", options: .backwards)?.lowerBound {
                        let afterAtSign = searchText.index(after: lastAtSign)
                        if afterAtSign < searchText.endIndex {
                            let query = String(searchText[afterAtSign...])
                            if !query.contains(" ") {
                                parent.onMentionTriggered(cursorPosition, query, startSearchIndex + lastAtSign.utf16Offset(in: searchText))
                                return
                            }
                        }
                    }
                }
                parent.onMentionTriggered(cursorPosition, "", -1)
            }
        }
    }
}

// Time logging view
struct TimeLogView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @State private var hours: String = ""
    @State private var comment: String = ""
    @State private var spentOn: Date = Date()
    @State private var activityName: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    let workPackageId: Int
    let onTimeLogged: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Time Details")) {
                    HStack {
                        Text("Hours")
                        Spacer()
                        TextField("0.0", text: $hours)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    DatePicker("Date", selection: $spentOn, displayedComponents: .date)
                    
                    TextField("Activity Name", text: $activityName)
                        .autocapitalization(.words)
                }
                
                Section(header: Text("Comment")) {
                    TextEditor(text: $comment)
                        .frame(minHeight: 100)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: logTime) {
                        Text("Log Time")
                    }
                    .disabled(hours.isEmpty || Double(hours) == 0 || activityName.isEmpty || isLoading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Log Time")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .overlay(Group {
                if isLoading {
                    ProgressView()
                }
            })
        }
    }
    
    private func logTime() {
        guard let hoursValue = Double(hours), 
              !activityName.isEmpty,
              let accessToken = appState.accessToken else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let url = URL(string: "\(appState.apiBaseURL)/time_entries")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Format date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let spentOnString = dateFormatter.string(from: spentOn)
        
        // Format hours in ISO 8601 duration format
        let formattedHours = "PT\(hoursValue)H"
        
        // Create payload
        var timeEntryData: [String: Any] = [
            "hours": formattedHours,
            "spentOn": spentOnString,
            "comment": ["raw": comment],
            "_links": [
                "workPackage": ["href": "/api/v3/work_packages/\(workPackageId)"]
            ]
        ]
        
        // Add manually entered activity name in the comment as a workaround
        let commentWithActivity = "Activity: \(activityName)\n\n\(comment)"
        timeEntryData["comment"] = ["raw": commentWithActivity]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: timeEntryData)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isLoading = false
                    
                    if let error = error {
                        errorMessage = "Error logging time: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        errorMessage = "Invalid response"
                        return
                    }
                    
                    // Print response data for debugging
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Time entry response: \(responseString)")
                    }
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        onTimeLogged()
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        // Try to extract error message from response
                        if let data = data, 
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? String {
                            errorMessage = "Server error: \(message)"
                        } else {
                            errorMessage = "Error logging time: HTTP \(httpResponse.statusCode)"
                        }
                    }
                }
            }.resume()
        } catch {
            isLoading = false
            errorMessage = "Error encoding time entry data: \(error.localizedDescription)"
        }
    }
}

// Attachments view to display and manage attachments
struct AttachmentsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var attachmentToDelete: Attachment?
    let workPackageId: Int
    let attachments: [Attachment]
    let onAttachmentDeleted: () -> Void
    
    var body: some View {
        attachmentsContentView
            .navigationTitle("Attachments")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Delete Attachment"),
                    message: Text("Are you sure you want to delete this attachment? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let attachment = attachmentToDelete {
                            deleteAttachment(attachment)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .overlay(Group {
                if isLoading {
                    ProgressView()
                }
            })
    }
    
    @ViewBuilder
    private var attachmentsContentView: some View {
        NavigationView {
            List {
                if attachments.isEmpty {
                    Text("No attachments found")
                        .italic()
                        .foregroundColor(.secondary)
                } else {
                    ForEach(attachments) { attachment in
                        attachmentRowView(for: attachment)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func attachmentRowView(for attachment: Attachment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(attachment.fileName)
                    .font(.headline)
                Spacer()
                
                // Delete button
                Button(action: {
                    attachmentToDelete = attachment
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Text(formattedFileSize(attachment.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(attachment.contentType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let description = attachment.description, let rawText = description.raw, !rawText.isEmpty {
                Text(rawText)
                    .font(.caption)
                    .padding(.top, 4)
            }
            
            // Download button - using the new href property
            Button(action: {
                downloadAttachment(from: attachment.href, fileName: attachment.fileName)
            }) {
                Label("Download", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
    
    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    private func downloadAttachment(from urlPath: String, fileName: String) {
        guard let accessToken = appState.accessToken else {
            return
        }
        
        // Handle both absolute and relative URLs properly
        let urlString = urlPath.hasPrefix("http") 
            ? urlPath 
            : appState.constructApiUrl(path: urlPath)
        
        print("Downloading attachment from URL: \(urlString)")
        
        guard let url = URL(string: urlString) else { 
            print("Error: Invalid download URL: \(urlString)")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        isLoading = true
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("Error downloading: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                // Save to a temporary location
                let tempDirectoryURL = FileManager.default.temporaryDirectory
                let fileURL = tempDirectoryURL.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    
                    // Share the file
                    let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    
                    // Present the activity view controller
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(activityVC, animated: true)
                    }
                } catch {
                    print("Error saving file: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func deleteAttachment(_ attachment: Attachment) {
        guard let accessToken = appState.accessToken else {
            return
        }
        
        // Use the attachment ID to construct a delete URL
        let urlString = "\(appState.apiBaseURL)/attachments/\(attachment.id)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        isLoading = true
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("Error deleting attachment: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Successfully deleted
                    onAttachmentDeleted()
                } else {
                    print("Error deleting attachment: HTTP \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}

// Attachment upload view
struct AttachmentUploadView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    @State private var isShowingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var fileName: String = ""
    @State private var fileDescription: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progressValue: Float = 0.0
    let workPackageId: Int
    let addAttachmentLink: String
    let onAttachmentAdded: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("File")) {
                    Button(action: {
                        isShowingFilePicker = true
                    }) {
                        HStack {
                            Text(selectedFileURL != nil ? "Change File" : "Select File")
                                .foregroundColor(.blue)
                            Spacer()
                            if let fileURL = selectedFileURL {
                                Text(fileURL.lastPathComponent)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if selectedFileURL != nil {
                        TextField("File Name", text: $fileName)
                    }
                }
                
                if selectedFileURL != nil {
                    Section(header: Text("Description")) {
                        TextEditor(text: $fileDescription)
                            .frame(minHeight: 100)
                    }
                    
                    if isLoading {
                        Section {
                            ProgressView(value: progressValue)
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                    }
                    
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section {
                        Button(action: uploadFile) {
                            Text("Upload Attachment")
                        }
                        .disabled(selectedFileURL == nil || isLoading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Add Attachment")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: [.image, .text, .pdf, .spreadsheet, .audio, .movie, .archive, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let selectedURL = urls.first {
                        self.selectedFileURL = selectedURL
                        self.fileName = selectedURL.lastPathComponent
                    }
                case .failure(let error):
                    self.errorMessage = "Error selecting file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func uploadFile() {
        guard let fileURL = selectedFileURL,
              let accessToken = appState.accessToken else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        progressValue = 0.1
        
        // First, read the file data
        do {
            // Start accessing security-scoped resource
            let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // Now read the file data
            let fileData = try Data(contentsOf: fileURL)
            progressValue = 0.2
            
            // Get the file's MIME type
            let mimeType = getMimeType(for: fileURL)
            
            // Debug: Log the file size and mime type
            print("File size: \(fileData.count) bytes, MIME type: \(mimeType)")
            
            // Construct the full URL
            let urlString = appState.constructApiUrl(path: addAttachmentLink)
            print("Constructed attachment URL: \(urlString)")
            guard let url = URL(string: urlString) else {
                errorMessage = "Invalid API URL"
                isLoading = false
                return
            }
            
            // Debug: Print the upload URL
            print("Upload URL: \(url.absoluteString)")
            
            // Create the upload request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            // Create multipart form data - using a more reliable approach
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // Add metadata part
            let metadataDict: [String: String] = [
                "fileName": fileName,
                "description": fileDescription
            ]
            
            if let metadataJSON = try? JSONSerialization.data(withJSONObject: metadataDict) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
                body.append(metadataJSON)
                body.append("\r\n".data(using: .utf8)!)
                
                // Debug: Print metadata JSON
                if let metadataStr = String(data: metadataJSON, encoding: .utf8) {
                    print("Metadata: \(metadataStr)")
                }
            }
            
            // Add file part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            
            // Close the boundary
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Set the HTTP body
            request.httpBody = body
            
            // Debug: Log request headers
            print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
            
            progressValue = 0.4
            
            // Send the request
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    progressValue = 0.9
                    
                    // Debug: Print raw response
                    if let data = data, let responseStr = String(data: data, encoding: .utf8) {
                        print("Response: \(responseStr)")
                    }
                    
                    if let error = error {
                        errorMessage = "Error uploading file: \(error.localizedDescription)"
                        print("Upload error: \(error)")
                        isLoading = false
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        errorMessage = "Invalid response"
                        isLoading = false
                        return
                    }
                    
                    // Debug: Print HTTP status code
                    print("HTTP Status: \(httpResponse.statusCode)")
                    print("HTTP Headers: \(httpResponse.allHeaderFields)")
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        progressValue = 1.0
                        onAttachmentAdded()
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        // Try to extract error message from response
                        if let data = data {
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                print("Error JSON: \(json)")
                                
                                if let errorType = json["_type"] as? String, errorType == "Error",
                                   let message = json["message"] as? String {
                                    errorMessage = "Server error: \(message)"
                                    print("OpenProject API error: \(message)")
                                } else if let message = json["message"] as? String {
                                    errorMessage = "Server error: \(message)"
                                } else if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                                    errorMessage = "Server error: \(errors.description)"
                                } else {
                                    errorMessage = "Error uploading file: HTTP \(httpResponse.statusCode)"
                                }
                            } else if let responseText = String(data: data, encoding: .utf8) {
                                errorMessage = "Error: \(responseText)"
                                print("Raw error response: \(responseText)")
                            } else {
                                errorMessage = "Error uploading file: HTTP \(httpResponse.statusCode)"
                            }
                        } else {
                            errorMessage = "Error uploading file: HTTP \(httpResponse.statusCode)"
                        }
                        isLoading = false
                    }
                }
            }.resume()
            
        } catch {
            isLoading = false
            errorMessage = "Error reading file: \(error.localizedDescription)"
            print("File read error: \(error)")
        }
    }
    
    private func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension
        
        if let uti = UTType(filenameExtension: pathExtension),
           let mimeType = uti.preferredMIMEType {
            return mimeType
        }
        
        // Fallback for common types
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "txt":
            return "text/plain"
        case "rtf":
            return "application/rtf"
        case "html", "htm":
            return "text/html"
        case "xml":
            return "application/xml"
        case "json":
            return "application/json"
        case "zip":
            return "application/zip"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "ppt", "pps":
            return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default:
            return "application/octet-stream"
        }
    }
}

// Activity Row component
struct ActivityRow: View {
    let activity: Activity
    @State private var refreshID = UUID() // Add state to trigger view refresh
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.user.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .id(refreshID) // Use ID to force refresh when this changes
                Spacer()
                Text(dateFormatter.string(from: activity.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let comment = activity.comment, let content = comment.raw {
                    Text(content)
                        .font(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let details = activity.details, !details.isEmpty {
                    // Show details if present
                    ForEach(0..<details.count, id: \.self) { index in
                        let detail = details[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.raw)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Fallback for other activity types
                    Text("Activity: \(activity.type)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserCacheUpdated"))) { _ in
            // When user cache updates, refresh the view with a new UUID
            refreshID = UUID()
        }
    }
}

struct ActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var activities: [Activity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    let workPackageId: Int
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if activities.isEmpty {
                Text("No activities found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            // Ensure token is set in UserCache with explicit printing for debugging
            if let token = appState.accessToken {
                print("🔑 Setting token in UserCache from ActivitiesView: \(token.prefix(5))...")
                UserCache.shared.setToken(token)
                
                // Force notification about token update
                NotificationCenter.default.post(name: NSNotification.Name("UserCacheUpdated"), object: nil)
            } else {
                print("⛔️ No access token available in ActivitiesView.onAppear()")
            }
            
            loadActivities()
        }
    }
    
    private func loadActivities() {
        // Make sure token is set before loading activities
        if let token = appState.accessToken {
            UserCache.shared.setToken(token)
        }
        
        isLoading = true
        errorMessage = nil
        
        guard let accessToken = appState.accessToken else {
            isLoading = false
            errorMessage = "No access token available"
            return
        }
        
        // Construct the URL for fetching activities
        let baseURL = URL(string: "https://project.anyitthing.com")!
        let activitiesURL = baseURL.appendingPathComponent("/api/v3/work_packages/\(workPackageId)/activities")
        
        print("🔍 Loading activities from URL: \(activitiesURL.absoluteString)")
        
        var request = URLRequest(url: activitiesURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to load activities: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                // Debug response
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Activities API HTTP status: \(httpResponse.statusCode)")
                }
                
                print("📦 Activities API data size: \(data.count) bytes")
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    let previewLength = min(jsonString.count, 500)
                    let preview = jsonString.prefix(previewLength) + (jsonString.count > previewLength ? "..." : "")
                    print("📄 Activities API response: \(preview)")
                }
                
                do {
                    // First parse as dictionary to examine structure
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🧩 Activities API JSON structure: \(json.keys)")
                        
                        if let embedded = json["_embedded"] as? [String: Any],
                           let elements = embedded["elements"] as? [[String: Any]] {
                            print("✅ Found \(elements.count) activities in the response")
                            
                            // Check the first element's structure
                            if let firstElement = elements.first {
                                print("🔍 First activity structure: \(firstElement.keys)")
                                
                                // Debug links section
                                if let links = firstElement["_links"] as? [String: Any] {
                                    print("📎 Activity links: \(links.keys)")
                                    if let user = links["user"] as? [String: Any] {
                                        print("👤 User link: \(user)")
                                    }
                                }
                            }
                        } else {
                            print("❌ Could not find elements in _embedded")
                        }
                    }
                    
                    // Now try to decode into the model
                    let decoder = JSONDecoder()
                    let activityCollection = try decoder.decode(ActivityCollection.self, from: data)
                    
                    // Sort activities by createdAt descending before assigning
                    let sortedActivities = activityCollection.embedded.elements.sorted { $0.createdAt > $1.createdAt }
                    self.activities = sortedActivities
                    
                    print("✅ Successfully loaded and sorted \(self.activities.count) activities")
                } catch {
                    print("❌ Error decoding activities: \(error)")
                    
                    // Try to examine raw structure for debugging
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let embedded = json["_embedded"] as? [String: Any],
                       let elements = embedded["elements"] as? [[String: Any]] {
                        
                        print("🔍 Activities raw structure:")
                        for (index, element) in elements.prefix(2).enumerated() {
                            print("  Activity \(index): Keys = \(element.keys)")
                        }
                    }
                    
                    self.errorMessage = "Error parsing activities: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

// Status selection view
struct StatusSelectionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    let currentStatus: Int?
    let statuses: [WorkPackageStatus]
    let onSelect: (Int?) -> Void
    
    var body: some View {
        NavigationView {
            List {                
                ForEach(statuses) { status in
                    Button {
                        onSelect(status.id)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: status.color) ?? .gray)
                                .frame(width: 12, height: 12)
                            
                            Text(status.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if currentStatus == status.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Status")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// Priority selection view
struct PrioritySelectionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    let currentPriority: Int?
    let priorities: [WorkPackagePriority]
    let onSelect: (Int?) -> Void
    
    var body: some View {
        NavigationView {
            List {                
                ForEach(priorities) { priority in
                    Button {
                        onSelect(priority.id)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            if let color = priority.color {
                                Circle()
                                    .fill(Color(hex: color) ?? .gray)
                                    .frame(width: 12, height: 12)
                            }
                            
                            Text(priority.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if currentPriority == priority.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Priority")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
