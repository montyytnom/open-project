//
//  ProjectsView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
import Combine

// Import the ProjectStatus model

struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText: String = ""
    @State private var showingCreateProjectSheet = false
    @State private var hideInactiveProjects: Bool = true
    
    private var filteredProjects: [Project] {
        var projects = appState.projects
        
        // Apply inactive filter if enabled
        if hideInactiveProjects {
            projects = projects.filter { $0.active }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            projects = projects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return projects
    }
    
    var body: some View {
        NavigationView {
            projectListView
                .navigationTitle("Projects")
                .navigationBarItems(trailing: 
                    Button(action: {
                        showingCreateProjectSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                )
                .sheet(isPresented: $showingCreateProjectSheet) {
                    CreateProjectView()
                        .environmentObject(appState)
                }
        }
        .searchable(text: $searchText, prompt: "Search projects")
        .onAppear {
            loadProjects()
        }
    }
    
    // MARK: - Subviews
    private var projectListView: some View {
        ZStack {
            VStack {
                // Filter toggle
                HStack {
                    Toggle("Hide inactive projects", isOn: $hideInactiveProjects)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                .background(Color(UIColor.systemGroupedBackground))
                
                List {
                    ForEach(filteredProjects) { project in
                        projectRowView(for: project)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    loadProjects()
                }
            }
            
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
            
            if filteredProjects.isEmpty && !appState.isLoading {
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No Projects Found")
                        .font(.headline)
                    if !searchText.isEmpty {
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else if hideInactiveProjects {
                        Text("Try showing inactive projects")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Create a new project to get started")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
    }
    
    private func projectRowView(for project: Project) -> some View {
        NavigationLink(destination: ProjectDetailView(project: project)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                
                if let description = project.description, description.raw.count > 0 {
                    Text(description.raw)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Text(project.identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !project.active {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func loadProjects() {
        appState.fetchProjects()
    }
    
    private func deleteProjects(at offsets: IndexSet) {
        // Convert offsets to project IDs
        let projectsToDelete = offsets.map { filteredProjects[$0] }
        
        for project in projectsToDelete {
            deleteProject(project)
        }
    }
    
    private func deleteProject(_ project: Project) {
        guard let token = appState.accessToken,
              let deleteLink = project.links.delete?.href else { return }
        
        var request = URLRequest(url: URL(string: deleteLink)!)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { responseData, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    appState.errorMessage = "Error deleting project: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Successfully deleted
                    appState.projects.removeAll { $0.id == project.id }
                    
                    // If the deleted project was the current project, clear it
                    if appState.currentProject?.id == project.id {
                        appState.currentProject = nil
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    if let responseData = responseData {
                        do {
                            let errorResponse = try JSONDecoder().decode(APIErrorResponse.self, from: responseData)
                            appState.errorMessage = errorResponse.message ?? "Failed to delete project"
                        } catch {
                            appState.errorMessage = "Failed to delete project. Status code: \(httpResponse.statusCode)"
                        }
                    } else {
                        appState.errorMessage = "Failed to delete project. Status code: \(httpResponse.statusCode)"
                    }
                } else {
                    appState.errorMessage = "Failed to delete project. Unknown error occurred."
                }
            }
        }.resume()
    }
}

struct ProjectRow: View {
    let project: Project
    
    // Add a computed property to extract the custom status
    private var customStatus: (id: Int?, name: String) {
        // Print debug info
        print("Project: \(project.name)")
        print("Links: \(project.links)")
        
        // First try to get customField3
        if let customField3 = project.links.customField3?.href {
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
            print("No customField3 found for project \(project.name)")
        }
        
        // If customField3 is not available, try regular status
        if let status = project.links.status?.title {
            print("Regular status found: \(status)")
            return (nil, status)
        } else if let statusHref = project.links.status?.href {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.headline)
                
                Spacer()
                
                // Active status indicator
                if !project.active {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray)
                        .cornerRadius(4)
                }
            }
            
            HStack {
                Text("ID: \(project.identifier)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Display custom status
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(title: customStatus.name))
                        .frame(width: 10, height: 10)
                    
                    Text(customStatus.name)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(title: customStatus.name).opacity(0.2))
                        .cornerRadius(4)
                        .foregroundColor(statusColor(title: customStatus.name))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // Determine color based on status title
    private func statusColor(title: String?) -> Color {
        guard let title = title?.lowercased() else { return .blue }
        
        if title.contains("estimating") {
            return .blue
        } else if title.contains("waiting on client") {
            return .orange
        } else if title.contains("waiting on equipment") {
            return .purple
        } else if title.contains("in progress") {
            return .green
        } else if title.contains("completed") {
            return .gray
        }
        
        return .blue
    }
}

struct CreateProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    
    @State private var name: String = ""
    @State private var identifier: String = ""
    @State private var description: String = ""
    @State private var isPublic: Bool = true
    @State private var selectedStatus: ProjectStatus = ProjectStatus.onTrack
    @State private var statusExplanation: String = ""
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
    
    var body: some View {
        NavigationView {
            // MARK: - Form content
            formContent
                .navigationTitle("Create Project")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createProject()
                        }
                        .disabled(name.isEmpty || identifier.isEmpty || isSubmitting)
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
    
    // MARK: - Form content view
    private var formContent: some View {
        Form {
            // MARK: - Project details section
            projectDetailsSection
            
            // MARK: - Status section
            statusSection
            
            // MARK: - Custom Fields section
            customFieldSection
            
            // MARK: - Visibility section
            Section(header: Text("Visibility")) {
                Toggle("Public", isOn: $isPublic)
            }
            
            // MARK: - Error section
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Custom Fields section
    private var customFieldSection: some View {
        Section(header: Text("Custom Fields")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status (Required)")
                    .font(.headline)
                
                Text("Required")
                    .font(.caption)
                    .foregroundColor(.red)
                
                Text("Note: This server requires a custom field status to be set. Try different options if creating a project fails.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                Picker("Custom Status", selection: $selectedCustomStatus) {
                    ForEach(CustomFieldStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Project details section
    private var projectDetailsSection: some View {
        Section(header: Text("Project Details")) {
            TextField("Name", text: $name)
            
            TextField("Identifier", text: $identifier)
                .textInputAutocapitalization(.never)
                .onChange(of: name) { newValue in
                    // Auto-populate identifier based on name if not manually entered
                    if identifier.isEmpty {
                        identifier = newValue
                            .lowercased()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: " ", with: "-")
                            // Remove special characters
                            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
                            .joined()
                    }
                }
            
            TextEditor(text: $description)
                .frame(minHeight: 100)
        }
    }
    
    // MARK: - Status section
    private var statusSection: some View {
        Section(header: Text("Status")) {
            Picker("Project Status", selection: $selectedStatus) {
                ForEach(ProjectStatus.allStatuses, id: \.id) { status in
                    Text(status.name).tag(status)
                }
            }
            
            TextField("Status Explanation", text: $statusExplanation)
        }
    }
    
    private func createProject() {
        guard let token = appState.accessToken else { return }
        isSubmitting = true
        errorMessage = nil
        
        // Prepare the request
        let url = URL(string: "\(appState.apiBaseURL)/projects")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create main request body with proper project structure
        var projectData: [String: Any] = [
            "name": name,
            "identifier": identifier,
            "public": isPublic
        ]
        
        // Create _links dictionary with status link
        let links: [String: Any] = [
            "status": [
                "href": "/api/v3/project_statuses/\(selectedStatus.id)"
            ],
            // Use numeric ID for customField3
            "customField3": [
                "href": "/api/v3/custom_options/\(selectedCustomStatus.id)"
            ]
        ]
        
        projectData["_links"] = links
        
        // Add description if provided
        if !description.isEmpty {
            projectData["description"] = [
                "raw": description
            ]
        }
        
        // Add status explanation if provided
        if !statusExplanation.isEmpty {
            projectData["statusExplanation"] = [
                "raw": statusExplanation
            ]
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: projectData)
            
            // Debug: Print the JSON body being sent
            if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                print("Creating project with JSON: \(jsonString)")
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    
                    if let error = error {
                        errorMessage = "Error: \(error.localizedDescription)"
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("HTTP Status: \(httpResponse.statusCode)")
                        
                        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                            // Project was created successfully
                            if let data = data {
                                do {
                                    let newProject = try JSONDecoder().decode(Project.self, from: data)
                                    appState.projects.append(newProject)
                                    dismiss()
                                } catch {
                                    print("Decoding error: \(error)")
                                    // Successfully created but couldn't parse response
                                    // Still consider it a success and refresh projects
                                    appState.fetchProjects()
                                    dismiss()
                                }
                            } else {
                                appState.fetchProjects()
                                dismiss()
                            }
                        } else {
                            // Server returned an error
                            if let data = data {
                                // Debug: Print error response
                                if let errorString = String(data: data, encoding: .utf8) {
                                    print("Error response: \(errorString)")
                                }
                                
                                do {
                                    let errorResponse = try JSONDecoder().decode(APIErrorResponse.self, from: data)
                                    errorMessage = errorResponse.message ?? "Failed to create project"
                                } catch {
                                    print("Error decoding error response: \(error)")
                                    errorMessage = "Failed to create project. Status code: \(httpResponse.statusCode)"
                                }
                            } else {
                                errorMessage = "Failed to create project. Status code: \(httpResponse.statusCode)"
                            }
                        }
                    }
                }
            }.resume()
        } catch {
            isSubmitting = false
            errorMessage = "Error encoding project data: \(error.localizedDescription)"
        }
    }
}

struct ProjectsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProjectsView()
                .environmentObject(AppState())
        }
    }
} 