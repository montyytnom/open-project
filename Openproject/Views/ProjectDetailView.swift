//
//  ProjectDetailView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
import Combine
import Foundation
import UserNotifications
import WebKit

// Define HTMLText locally if not available through imports
#if os(iOS) || os(macOS)
struct ProjectHTMLTextView: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textColor = .label // Use system label color for proper dark mode support
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Convert newlines to <br> tags to handle raw text input gracefully
        let htmlWithBreaks = html.replacingOccurrences(of: "\n", with: "<br>")
        print("--> HTMLTextView updateUIView: Received HTML (length: \(html.count)), Processed HTML: \(htmlWithBreaks)")
        
        // Clean specific OpenProject tags if necessary
        let cleanedHtml = htmlWithBreaks.replacingOccurrences(of: "<p class=\"op-uc-p\">", with: "<p>")
        
        // Add CSS to ensure text color adapts to system appearance
        let css = """
            <style>
                body {
                    color: \(UIColor.label.hexString);
                    font-family: -apple-system, system-ui;
                    font-size: 16px;
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
            print("--> HTMLTextView updateUIView: Set attributed string.")
        } else {
            uiView.text = cleanedHtml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            print("--> HTMLTextView updateUIView: Set plain text fallback.")
        }
    }
}

// Helper extension to get hex string from UIColor
extension UIColor {
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let rgb = Int(r * 255) << 16 | Int(g * 255) << 8 | Int(b * 255) << 0
        
        return String(format: "#%06x", rgb)
    }
}
#endif

// Import models directly

struct ProjectDetailView: View {
    @EnvironmentObject private var appState: AppState
    let project: Project
    @State private var showingEditProject = false
    @State private var refreshedProject: Project?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isLoadingMembers = false
    @State private var projectMembers: [ProjectMember] = []
    @State private var showingManageMembers = false
    
    // Compute the current project to use refreshed data if available
    private var currentProject: Project {
        refreshedProject ?? project
    }
    
    // Add a computed property to extract the custom status
    private var customStatus: (id: Int?, name: String) {
        // Print debug info
        print("Project detail: \(currentProject.name)")
        
        // First try to get customField3
        if let customField3 = currentProject.links.customField3?.href {
            print("Custom field 3 found: \(customField3)")
            let components = customField3.components(separatedBy: "/")
            if let last = components.last {
                // Try to convert to Int first
                if let customOptionId = Int(last) {
                    // Map the ID to our known statuses
                    switch customOptionId {
                    case 1: return (1, "Estimating")
                    case 2: return (2, "Waiting on Client")
                    case 3: return (3, "Waiting on Equipment")
                    case 4: return (4, "In Progress")
                    case 5: return (5, "Completed")
                    default: return (customOptionId, "Status \(customOptionId)")
                    }
                } else {
                    // Handle text-based status values
                    print("Non-numeric status value: \(last)")
                    let statusName = last.replacingOccurrences(of: "-", with: " ").capitalized
                    switch last.lowercased() {
                    case "estimating": return (1, "Estimating")
                    case "waiting-on-client", "waiting_on_client": return (2, "Waiting on Client")
                    case "waiting-on-equipment", "waiting_on_equipment": return (3, "Waiting on Equipment")
                    case "in-progress", "in_progress": return (4, "In Progress")
                    case "completed": return (5, "Completed")
                    default: return (nil, statusName)
                    }
                }
            }
        } else {
            print("No customField3 found for project \(currentProject.name)")
        }
        
        // If customField3 is not available, try regular status
        if let status = currentProject.links.status?.title {
            print("Regular status found: \(status)")
            return (nil, status)
        } else if let statusHref = currentProject.links.status?.href {
            print("Status href found: \(statusHref)")
            let components = statusHref.components(separatedBy: "/")
            if let statusId = components.last {
                // Map known status IDs
                switch statusId {
                case "on_track": return (nil, "On Track")
                case "at_risk": return (nil, "At Risk")
                case "off_track": return (nil, "Off Track")
                case "not_started": return (nil, "Not Started")
                case "finished": return (nil, "Finished")
                case "discontinued": return (nil, "Discontinued")
                default: return (nil, "Status: \(statusId)")
                }
            }
        }
        
        print("No status information found")
        // Provide a default status when nothing else is available
        return (nil, "In Progress")
    }
    
    // Helper for status color
    private func statusColor(status: String) -> Color {
        let lowercaseStatus = status.lowercased()
        
        if lowercaseStatus.contains("estimating") {
            return .blue
        } else if lowercaseStatus.contains("waiting on client") {
            return .orange
        } else if lowercaseStatus.contains("waiting on equipment") {
            return .purple
        } else if lowercaseStatus.contains("in progress") {
            return .green
        } else if lowercaseStatus.contains("completed") {
            return .gray
        }
        
        return .blue
    }
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Refreshing project data...")
                    .padding(.top, 50)
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Error parsing project data")
                        .font(.title3)
                        .fontWeight(.bold)
                        
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        
                    Button(action: {
                        refreshProjectData()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Project Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentProject.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Identifier: \(currentProject.identifier)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Status:")
                                .foregroundColor(.secondary)
                            
                            Text(customStatus.name)
                                .foregroundColor(statusColor(status: customStatus.name))
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(status: customStatus.name).opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        HStack {
                            Text(currentProject.active ? "Active" : "Inactive")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentProject.active ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(currentProject.active ? .green : .red)
                                .cornerRadius(4)
                            
                            Text(currentProject.isPublic ? "Public" : "Private")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentProject.isPublic ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                                .foregroundColor(currentProject.isPublic ? .blue : .gray)
                                .cornerRadius(4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    
                    // Description
                    if let description = currentProject.description, !description.raw.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            let _ = print("--> ProjectDetailView Body: Rendering Description - Raw: \(description.raw)") // DEBUG
                            Text(description.raw)
                                .font(.body)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 1)
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        
                        if let notes = currentProject.customField1, !notes.raw.isEmpty {
                            let _ = print("--> ProjectDetailView Body: Rendering Notes - Raw: \(notes.raw)") // DEBUG
                            Text(notes.raw)
                                .font(.body)
                        } else {
                            Text("No notes")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    
                    // Materials
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Materials")
                            .font(.headline)
                        
                        if let materials = currentProject.customField6, !materials.raw.isEmpty {
                            let _ = print("--> ProjectDetailView Body: Rendering Materials - HTML: \(materials.html)") // DEBUG
                            ProjectHTMLTextView(html: materials.html)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("materials-\(materials.html.hashValue)") // Force view update when HTML changes
                        } else {
                            Text("No materials")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    
                    // Members Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Members")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                loadProjectMembers()
                                showingManageMembers = true
                            }) {
                                Label("Manage", systemImage: "person.badge.plus")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                        }
                        
                        if isLoadingMembers {
                            ProgressView("Loading members...")
                                .padding(.vertical, 4)
                        } else if projectMembers.isEmpty {
                            Text("No members assigned")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.vertical, 4)
                        } else {
                            ForEach(projectMembers) { member in
                                HStack {
                                    Text(member.user.name)
                                        .font(.body)
                                    
                                    Spacer()
                                    
                                    // Show roles as tags
                                    if !member.roles.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(0..<min(2, member.roles.count), id: \.self) { index in
                                                Text(member.roles[index].name)
                                                    .font(.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.gray.opacity(0.2))
                                                    .cornerRadius(4)
                                            }
                                            
                                            // Show +X more if there are more than 2 roles
                                            if member.roles.count > 2 {
                                                Text("+\(member.roles.count - 2)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    
                    // Project Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Actions")
                            .font(.headline)
                        
                        Button(action: { showingEditProject = true }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Edit Project")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        
                        if currentProject.links.workPackages != nil {
                            NavigationLink(destination: WorkPackagesView(project: currentProject)) {
                                HStack {
                                    Image(systemName: "list.bullet")
                                    Text("Work Packages")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    
                    // Dates
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dates")
                            .font(.headline)
                        
                        HStack {
                            Text("Created:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatISODate(currentProject.createdAt))
                        }
                        
                        HStack {
                            Text("Updated:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatISODate(currentProject.updatedAt))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                }
                .padding()
            }
        }
        .navigationTitle(currentProject.name)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingEditProject) {
            EditProjectView(project: currentProject, isPresented: $showingEditProject) { updatedProject in
                // DEBUG: Print received updated project
                print("--> ProjectDetailView onSave: Received updated project - Desc: \(updatedProject.description?.raw ?? "nil"), Notes: \(updatedProject.customField1?.raw ?? "nil"), Materials HTML: \(updatedProject.customField6?.html ?? "nil")")
                self.refreshedProject = updatedProject
                if let index = self.appState.projects.firstIndex(where: { $0.id == updatedProject.id }) {
                    DispatchQueue.main.async {
                        self.appState.projects[index] = updatedProject
                    }
                }
            }
        }
        .sheet(isPresented: $showingManageMembers) {
            ManageMembersView(
                project: currentProject,
                currentMembers: projectMembers,
                isPresented: $showingManageMembers,
                onMembersUpdated: { updatedMembers in
                    // Update the members list when members are added or removed
                    projectMembers = updatedMembers
                }
            )
        }
        .onAppear {
            if refreshedProject == nil {
                refreshProjectData()
                loadProjectMembers()
            }
        }
        .refreshable {
            refreshProjectData()
            loadProjectMembers()
        }
        .alert(isPresented: .constant(errorMessage != nil), content: {
            Alert(title: Text("Error"), message: Text(errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")) {
                errorMessage = nil
            })
        })
    }
    
    // Method to fetch the latest project data
    private func refreshProjectData() {
        guard let accessToken = appState.accessToken else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let urlString = "\(appState.apiBaseURL)/projects/\(project.id)"
        guard let url = URL(string: urlString) else {
            isLoading = false
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.mainThreadSafe {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                do {
                    // Debug: Print response preview
                    if let responseString = String(data: data, encoding: .utf8) {
                        let previewLength = min(200, responseString.count)
                        print("Project data response: \(responseString.prefix(previewLength))...")
                    }
                    
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.errorMessage = "Invalid JSON structure"
                        return
                    }
                    
                    guard let id = json["id"] as? Int,
                          let name = json["name"] as? String,
                          let identifier = json["identifier"] as? String,
                          let active = json["active"] as? Bool,
                          let isPublic = json["public"] as? Bool,
                          let links = json["_links"] as? [String: Any] else {
                        self.errorMessage = "Missing required project fields"
                        return
                    }
                    
                    // Create project links
                    let projectLinks = ProjectLinks(
                        selfLink: self.extractLink(from: links, key: "self") ?? Link(href: "", title: nil, templated: nil, method: nil),
                        createWorkPackage: self.extractLink(from: links, key: "createWorkPackage"),
                        createWorkPackageImmediately: self.extractLink(from: links, key: "createWorkPackageImmediately"),
                        workPackages: self.extractLink(from: links, key: "workPackages"),
                        storages: self.extractLink(from: links, key: "storages"),
                        categories: self.extractLink(from: links, key: "categories"),
                        versions: self.extractLink(from: links, key: "versions"),
                        memberships: self.extractLink(from: links, key: "memberships"),
                        types: self.extractLink(from: links, key: "types"),
                        update: self.extractLink(from: links, key: "update"),
                        updateImmediately: self.extractLink(from: links, key: "updateImmediately"),
                        delete: self.extractLink(from: links, key: "delete"),
                        schema: self.extractLink(from: links, key: "schema"),
                        status: self.extractLink(from: links, key: "status"),
                        customField1: self.extractLink(from: links, key: "customField1"),
                        customField2: self.extractLink(from: links, key: "customField2"),
                        customField3: self.extractLink(from: links, key: "customField3"),
                        customField6: self.extractLink(from: links, key: "customField6"),
                        ancestors: self.extractLink(from: links, key: "ancestors"),
                        projectStorages: self.extractLink(from: links, key: "projectStorages"),
                        parent: self.extractLink(from: links, key: "parent")
                    )
                    
                    // Extract description if available
                    var projectDescription: ProjectDescription? = nil
                    if let description = json["description"] as? [String: Any],
                       let format = description["format"] as? String,
                       let raw = description["raw"] as? String,
                       let html = description["html"] as? String {
                        projectDescription = ProjectDescription(format: format, raw: raw, html: html)
                    }
                    
                    // Extract custom fields if available
                    var customField1: ProjectDescription? = nil
                    if let field = json["customField1"] as? [String: Any],
                       let format = field["format"] as? String,
                       let raw = field["raw"] as? String,
                       let html = field["html"] as? String {
                        customField1 = ProjectDescription(format: format, raw: raw, html: html)
                    }
                    
                    var customField2: ProjectDescription? = nil
                    if let field = json["customField2"] as? [String: Any],
                       let format = field["format"] as? String,
                       let raw = field["raw"] as? String,
                       let html = field["html"] as? String {
                        customField2 = ProjectDescription(format: format, raw: raw, html: html)
                    }
                    
                    // Add extraction for customField6
                    var customField6: ProjectDescription? = nil
                    if let field = json["customField6"] as? [String: Any],
                       let format = field["format"] as? String,
                       let raw = field["raw"] as? String,
                       let html = field["html"] as? String {
                        customField6 = ProjectDescription(format: format, raw: raw, html: html)
                    }
                    
                    // Create the refreshed project
                    let refreshedProject = Project(
                        id: id,
                        identifier: identifier, 
                        name: name,
                        active: active,
                        isPublic: isPublic,
                        description: projectDescription,
                        createdAt: json["createdAt"] as? String ?? "2023-01-01T00:00:00Z",
                        updatedAt: json["updatedAt"] as? String ?? "2023-01-01T00:00:00Z",
                        statusExplanation: nil,
                        customField1: customField1,
                        customField2: customField2,
                        customField6: customField6,
                        links: projectLinks
                    )
                    
                    self.refreshedProject = refreshedProject
                    
                    // Also update the project in appState if needed
                    if let index = self.appState.projects.firstIndex(where: { $0.id == id }) {
                        self.appState.projects[index] = refreshedProject
                    }
                } catch {
                    self.errorMessage = "Error parsing project data: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func formatISODate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return isoString
    }
    
    private func loadProjectMembers() {
        isLoadingMembers = true
        projectMembers.removeAll()
        
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoadingMembers = false
            return
        }
        
        let projectId = project.id
        // Use the correct URL format with filters
        let membersEndpoint = "\(appState.apiBaseURL)/memberships?filters=[{\"project\":{\"operator\":\"=\",\"values\":[\"\(projectId)\"]}}]"
        
        guard let url = URL(string: membersEndpoint) else {
            errorMessage = "Invalid URL format"
            isLoadingMembers = false
            return
        }
        
        print("Fetching project members from: \(membersEndpoint)")
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.mainThreadSafe {
                isLoadingMembers = false
                
                if let error = error {
                    errorMessage = "Error fetching project members: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                        print("Project members received: \(data.count) bytes")
                        if let dataString = String(data: data, encoding: .utf8) {
                            print("Project members preview: \(String(dataString.prefix(200)))...")
                        }
                        
                        // Print detailed JSON structure
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("JSON keys at root: \(json.keys.sorted().joined(separator: ", "))")
                            
                            if let embedded = json["_embedded"] as? [String: Any] {
                                print("JSON keys in _embedded: \(embedded.keys.sorted().joined(separator: ", "))")
                                
                                if let elements = embedded["elements"] as? [[String: Any]], !elements.isEmpty {
                                    let firstElement = elements[0]
                                    print("First element keys: \(firstElement.keys.sorted().joined(separator: ", "))")
                                    
                                    if let firstElementEmbedded = firstElement["_embedded"] as? [String: Any] {
                                        print("First element _embedded keys: \(firstElementEmbedded.keys.sorted().joined(separator: ", "))")
                                    }
                                    
                                    if let firstElementLinks = firstElement["_links"] as? [String: Any] {
                                        print("First element _links keys: \(firstElementLinks.keys.sorted().joined(separator: ", "))")
                                    }
                                }
                            }
                        }
                        
                        do {
                            let membershipCollection = try JSONDecoder().decode(MembershipCollection.self, from: data)
                            self.projectMembers = membershipCollection.embedded.elements
                            print("Project members loaded successfully: \(self.projectMembers.count) members")
                        } catch {
                            print("Error decoding project members: \(error)")
                            // Try to manually decode the JSON to see what we're getting
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                print("JSON structure: \(json.keys)")
                                
                                // Try to manually extract members
                                if let embedded = json["_embedded"] as? [String: Any],
                                   let elements = embedded["elements"] as? [[String: Any]] {
                                    
                                    var parsedMembers: [ProjectMember] = []
                                    
                                    for element in elements {
                                        // Let's manually create a JSON structure we can decode
                                        var memberJSON: [String: Any] = [:]
                                        
                                        if let memberId = element["id"] as? Int {
                                            memberJSON["id"] = memberId
                                            
                                            if let links = element["_links"] as? [String: Any],
                                               let principal = links["principal"] as? [String: Any] {
                                                memberJSON["_links"] = ["principal": principal]
                                            }
                                            
                                            if let embedded = element["_embedded"] as? [String: Any],
                                               let roles = embedded["roles"] as? [[String: Any]] {
                                                memberJSON["_embedded"] = ["roles": roles]
                                            }
                                            
                                            // Try to encode and decode this member JSON
                                            do {
                                                let memberData = try JSONSerialization.data(withJSONObject: memberJSON)
                                                let member = try JSONDecoder().decode(ProjectMember.self, from: memberData)
                                                parsedMembers.append(member)
                                            } catch {
                                                print("Error parsing individual member: \(error)")
                                            }
                                        }
                                    }
                                    
                                    if !parsedMembers.isEmpty {
                                        print("Successfully parsed \(parsedMembers.count) members manually")
                                        self.projectMembers = parsedMembers
                                    } else {
                                        errorMessage = "Error parsing project members"
                                    }
                                } else {
                                    errorMessage = "Error parsing project members"
                                }
                            } else {
                                errorMessage = "Error parsing project members"
                            }
                        }
                    } else {
                        errorMessage = "Failed to fetch project members. Status code: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
    
    private func mainThreadSafe(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private func extractLink(from links: [String: Any], key: String) -> Link? {
        guard let link = links[key] as? [String: Any] else {
            return nil
        }
        
        let href = link["href"] as? String ?? ""
        let title = link["title"] as? String
        let templated = link["templated"] as? Bool
        let method = link["method"] as? String
        
        return Link(href: href, title: title, templated: templated, method: method)
    }
}

// ManageMembersView has been moved to its own file - ManageMembersView.swift

struct EditProjectView: View {
    @EnvironmentObject private var appState: AppState
    let project: Project
    @Binding var isPresented: Bool
    var onSave: (Project) -> Void
    
    @State private var name: String
    @State private var description: String
    @State private var notes: String
    @State private var materials: String
    @State private var isPublic: Bool
    @State private var isActive: Bool
    @State private var selectedStatus: ProjectStatus
    @State private var statusExplanation: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    // Hardcoded custom field options for status selection
    enum CustomFieldStatus: Int, CaseIterable, Identifiable {
        case estimating = 1
        case waitingOnClient = 2
        case waitingOnEquipment = 3
        case inProgress = 4
        case completed = 5
        
        var id: Int { rawValue }
        
        var displayName: String {
            switch self {
            case .estimating: return "Estimating"
            case .waitingOnClient: return "Waiting on Client"
            case .waitingOnEquipment: return "Waiting on Equipment"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            }
        }
    }
    
    @State private var selectedCustomStatus: CustomFieldStatus = .estimating
    
    // Initialize with project values
    init(project: Project, isPresented: Binding<Bool>, onSave: @escaping (Project) -> Void) {
        self.project = project
        self._isPresented = isPresented
        self.onSave = onSave
        
        // Initialize state variables with project values
        self._name = State(initialValue: project.name)
        self._description = State(initialValue: project.description?.raw ?? "")
        self._notes = State(initialValue: project.customField1?.raw ?? "")
        self._materials = State(initialValue: project.customField6?.raw ?? "")
        self._isPublic = State(initialValue: project.isPublic)
        self._isActive = State(initialValue: project.active)
        self._statusExplanation = State(initialValue: project.statusExplanation?.raw ?? "")
        
        // Determine initial status based on project._links.status.href
        // Corrected: Get the String ID from the URL and compare String to String
        let statusIDString = project.links.status?.href?.split(separator: "/").last.map(String.init) ?? ""
        // Corrected: Use .first(where:) with String comparison and fallback to a valid static instance
        let initialStatus = ProjectStatus.allStatuses.first { $0.id == statusIDString } ?? ProjectStatus.onTrack // Use onTrack as default
        self._selectedStatus = State(initialValue: initialStatus)
        
        // Determine initial custom status based on project._links.customField3.href
        let customStatusID = project.links.customField3?.href?.split(separator: "/").last.map { Int($0) ?? 0 } ?? 0
        self._selectedCustomStatus = State(initialValue: CustomFieldStatus(rawValue: customStatusID) ?? .inProgress) // Default if not found
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Project details section
                Section(header: Text("Project Details")) {
                    TextField("Name", text: $name)
                    
                    Text("Description:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                    
                    Text("Notes:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                    
                    Text("Materials:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $materials)
                        .frame(minHeight: 100)
                    
                    Toggle("Active", isOn: $isActive)
                    Toggle("Public", isOn: $isPublic)
                }
                
                // Status section
                Section(header: Text("Status")) {
                    Picker("Project Status", selection: $selectedStatus) {
                        ForEach(ProjectStatus.allStatuses, id: \.id) { status in
                            Text(status.name).tag(status)
                        }
                    }
                    
                    TextField("Status Explanation", text: $statusExplanation)
                }
                
                // Custom Fields section
                Section(header: Text("Custom Fields")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status (Required)")
                            .font(.headline)
                        
                        Text("Required")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        Picker("Custom Status", selection: $selectedCustomStatus) {
                            ForEach(CustomFieldStatus.allCases) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.vertical, 4)
                    }
                }
                
                // Error section
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        updateProject()
                    }
                    .disabled(name.isEmpty || isSubmitting)
                }
            }
            .disabled(isSubmitting)
            .overlay(
                Group {
                    if isSubmitting {
                        ProgressView()
                    }
                }
            )
        }
    }
    
    private func updateProject() {
        guard let token = appState.accessToken else {
            errorMessage = "No access token available"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        
        let projectId = project.id
        let projectEndpoint = "/projects/\(projectId)"
        
        guard let apiUrl = URL(string: "\(appState.apiBaseURL)\(projectEndpoint)") else {
            errorMessage = "Invalid URL format"
            isSubmitting = false
            return
        }
        
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare payload
        var projectData: [String: Any] = [
            "name": name,
            "active": isActive,
            "public": isPublic,
            "_links": [
                "status": ["href": "/api/v3/project_statuses/\(selectedStatus.id)"],
                "customField3": ["href": "/api/v3/custom_options/\(selectedCustomStatus.id)"]
            ]
        ]

        // Add optional fields if not empty
        if !description.isEmpty { projectData["description"] = ["raw": description] }
        if !notes.isEmpty { projectData["customField1"] = ["raw": notes] }
        if !materials.isEmpty { projectData["customField6"] = ["raw": materials] }
        if !statusExplanation.isEmpty { projectData["statusExplanation"] = ["raw": statusExplanation] }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: projectData)
            
            if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                print("Updating project \(projectId) with JSON: \(jsonString)")
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    
                    if let error = error {
                        self.errorMessage = "Error updating project: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = "Invalid response from server."
                        return
                    }
                    
                    print("Update Project Response Status: \(httpResponse.statusCode)")
                    
                    if (200...299).contains(httpResponse.statusCode) {
                        print("Project updated successfully via API")
                        
                        // Construct the updated project object locally for the callback
                        let updatedProject = Project(
                            id: project.id,
                            identifier: project.identifier,
                            name: name,
                            active: isActive,
                            isPublic: isPublic,
                            description: description.isEmpty ? nil : ProjectDescription(format: "markdown", raw: description, html: ""),
                            createdAt: project.createdAt,
                            updatedAt: ISO8601DateFormatter().string(from: Date()),
                            statusExplanation: statusExplanation.isEmpty ? nil : ProjectDescription(format: "markdown", raw: statusExplanation, html: ""),
                            customField1: notes.isEmpty ? nil : ProjectDescription(format: "markdown", raw: notes, html: notes),
                            customField2: project.customField2,
                            customField6: materials.isEmpty ? nil : ProjectDescription(format: "markdown", raw: materials, html: materials),
                            links: ProjectLinks(
                                selfLink: project.links.selfLink,
                                createWorkPackage: project.links.createWorkPackage,
                                createWorkPackageImmediately: project.links.createWorkPackageImmediately,
                                workPackages: project.links.workPackages,
                                storages: project.links.storages,
                                categories: project.links.categories,
                                versions: project.links.versions,
                                memberships: project.links.memberships,
                                types: project.links.types,
                                update: project.links.update,
                                updateImmediately: project.links.updateImmediately,
                                delete: project.links.delete,
                                schema: project.links.schema,
                                status: Link(href: "/api/v3/project_statuses/\(selectedStatus.id)", title: selectedStatus.name, templated: nil, method: nil),
                                customField1: project.links.customField1,
                                customField2: project.links.customField2,
                                customField3: Link(href: "/api/v3/custom_options/\(selectedCustomStatus.id)", title: selectedCustomStatus.displayName, templated: nil, method: nil),
                                customField6: project.links.customField6,
                                ancestors: project.links.ancestors,
                                projectStorages: project.links.projectStorages,
                                parent: project.links.parent
                            )
                        )
                        
                        // DEBUG: Print project being sent to callback
                        print("--> EditProjectView updateProject: Calling onSave with - Desc: \(updatedProject.description?.raw ?? "nil"), Notes: \(updatedProject.customField1?.raw ?? "nil"), Materials HTML: \(updatedProject.customField6?.html ?? "nil")")

                        self.onSave(updatedProject)
                        self.isPresented = false
                    } else {
                        // Handle non-2xx responses
                        var errorMsg = "Error updating project (Status: \(httpResponse.statusCode))"
                        if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                            errorMsg += "\nResponse: \(responseBody)"
                            print(errorMsg) // Print detailed error
                            // Try parsing APIErrorResponse
                            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                                self.errorMessage = errorResponse.message ?? errorMsg
                            } else {
                                self.errorMessage = errorMsg
                            }
                        } else {
                             self.errorMessage = errorMsg
                        }
                    }
                }
            }.resume()
            
        } catch {
            errorMessage = "Failed to encode project data: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
} 