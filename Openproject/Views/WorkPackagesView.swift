//
//  WorkPackagesView.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import SwiftUI
import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

// HTMLText component for rendering HTML consistently across the app
struct HTMLText: UIViewRepresentable {
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
        // Clean HTML content to handle potential issues
        let cleanedHtml = cleanHtml(html)
        
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
        } else {
            // Fallback to plain text with HTML tags removed
            uiView.text = cleanedHtml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
    }
    
    // Function to clean HTML content
    private func cleanHtml(_ html: String) -> String {
        // If needed, perform additional HTML cleaning here
        return html
    }
}

// Import models directly - this is an alternative to using the import-fix helper

struct WorkPackageRow: View {
    let workPackage: WorkPackage
    let types: [WorkPackageType]
    let statuses: [WorkPackageStatus]
    
    private var workPackageType: WorkPackageType? {
        guard let typeLink = workPackage.links.type,
              let href = typeLink.href,
              let typeId = extractIdFromHref(href) else {
            return nil
        }
        
        return types.first { $0.id == typeId }
    }
    
    private var workPackageStatus: WorkPackageStatus? {
        guard let statusLink = workPackage.links.status,
              let href = statusLink.href,
              let statusId = extractIdFromHref(href) else {
            return nil
        }
        
        return statuses.first { $0.id == statusId }
    }
    
    private func extractIdFromHref(_ href: String) -> Int? {
        let components = href.split(separator: "/")
        if let last = components.last, let id = Int(last) {
            return id
        }
        return nil
    }
    
    private func statusColor(_ status: WorkPackageStatus?) -> Color {
        guard let status = status else { return .gray }
        return Color(hex: status.color) ?? .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workPackageType?.name ?? "Task")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(workPackageStatus))
                        .frame(width: 10, height: 10)
                    
                    Text(workPackageStatus?.name ?? "Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(workPackage.subject)
                .font(.headline)
                .lineLimit(2)
            
            if let dueDate = workPackage.dueDate {
                Text("Due: \(formattedDate(dueDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formattedDate(_ dateString: String) -> String {
        // First try parsing as ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        
        // If ISO8601 parsing fails, try simple date format (yyyy-MM-dd)
        let simpleDateFormatter = DateFormatter()
        simpleDateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = simpleDateFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        
        return dateString
    }
}

struct WorkPackagesView: View {
    let project: Project?
    
    @EnvironmentObject private var appState: AppState
    @State private var workPackages: [WorkPackage] = []
    @State private var workPackageTypes: [WorkPackageType] = []
    @State private var workPackageStatuses: [WorkPackageStatus] = []
    @State private var workPackagePriorities: [WorkPackagePriority] = []
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var isLoadingUsers = false
    @State private var users: [User] = []
    @State private var errorMessage: String?
    @State private var showingCreateWorkPackage = false
    @State private var projectsDict: [Int: Project] = [:] // Cache for project details
    
    private var filteredWorkPackages: [WorkPackage] {
        if searchText.isEmpty {
            return workPackages
        } else {
            return workPackages.filter { workPackage in
                workPackage.subject.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    // Group work packages by project
    private var workPackagesByProject: [(Project?, [WorkPackage])] {
        var grouped: [Int?: [WorkPackage]] = [:]
        
        for wp in filteredWorkPackages {
            let projectId = extractProjectId(from: wp)
            let project = projectId.flatMap { projectsDict[$0] }
            print("Work package: \(wp.subject), Project ID: \(String(describing: projectId)), Project Name: \(project?.name ?? "Not found")")
            grouped[projectId, default: []].append(wp)
        }
        
        let result = grouped.map { (projectId, workPackages) -> (Project?, [WorkPackage]) in
            let project = projectId.flatMap { projectsDict[$0] }
            print("Grouping - Project ID: \(String(describing: projectId)), Project Name: \(project?.name ?? "nil")")
            return (project, workPackages)
        }.sorted { first, second in
            if let firstName = first.0?.name, let secondName = second.0?.name {
                return firstName < secondName
            }
            return first.0 != nil && second.0 == nil
        }
        
        print("Final grouping:")
        for (project, packages) in result {
            print("Project: \(project?.name ?? "Unassigned") (ID: \(project?.id ?? -1)), Work Packages: \(packages.count)")
        }
        
        return result
    }
    
    private func extractProjectId(from workPackage: WorkPackage) -> Int? {
        if let projectLink = workPackage.links.project?.href {
            let components = projectLink.split(separator: "/")
            if let lastComponent = components.last,
               let id = Int(lastComponent) {
                print("Extracted project ID \(id) from link: \(projectLink)")
                return id
            }
        }
        return nil
    }
    
    var body: some View {
        List {
            if isLoading && workPackages.isEmpty {
                ProgressView("Loading work packages...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let errorMessage = errorMessage, workPackages.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if workPackages.isEmpty {
                Text("No work packages found")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(Array(zip(workPackagesByProject.indices, workPackagesByProject)), id: \.0) { index, projectGroup in
                    Section(header: Text(projectGroup.0?.name ?? "Unassigned Work Packages")) {
                        ForEach(projectGroup.1) { workPackage in
                            NavigationLink(destination: WorkPackageDetailView(workPackage: workPackage)) {
                                WorkPackageRow(workPackage: workPackage, types: workPackageTypes, statuses: workPackageStatuses)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            loadData()
        }
        .searchable(text: $searchText, prompt: "Search work packages")
        .navigationTitle(project == nil ? "All Work Packages" : "Work Packages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let project = project {
                    Button(action: {
                        showingCreateWorkPackage = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateWorkPackage) {
            if let project = project {
                CreateWorkPackageView(
                    project: project,
                    types: workPackageTypes,
                    statuses: workPackageStatuses,
                    priorities: workPackagePriorities,
                    onWorkPackageCreated: { newWorkPackage in
                        // Add the new work package to the list
                        workPackages.append(newWorkPackage)
                        // Sort the work packages by most recent first
                        workPackages.sort { $0.updatedAt > $1.updatedAt }
                        showingCreateWorkPackage = false
                        // Refresh the data to ensure we have the latest
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            loadData()
                        }
                    }
                )
            }
        }
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        isLoading = true
        
        // Load work packages
        loadWorkPackages { success in
            if success {
                loadWorkPackageTypes()
                loadWorkPackageStatuses()
                loadWorkPackagePriorities()
                
                // Explicitly load missing project details
                self.loadMissingProjectDetails {
                    // Mark loading as complete
                    self.isLoading = false
                    print("UI refreshed with project data")
                }
            } else {
                self.isLoading = false
            }
        }
    }
    
    private func loadWorkPackages(completion: @escaping (Bool) -> Void) {
        guard let token = appState.accessToken else {
            self.errorMessage = "No access token available"
            completion(false)
            return
        }
        
        // Load the work packages directly, without the two-step process
        var urlString: String
        
        if let project = project {
            if let workPackagesLink = project.links.workPackages?.href {
                if workPackagesLink.hasPrefix("/") || !workPackagesLink.lowercased().hasPrefix("http") {
                    urlString = appState.constructApiUrl(path: workPackagesLink)
                } else {
                    urlString = workPackagesLink
                }
            } else {
                urlString = appState.constructApiUrl(path: "/projects/\(project.id)/work_packages")
            }
            projectsDict[project.id] = project
        } else {
            urlString = appState.constructApiUrl(path: "/work_packages")
        }
        
        if !urlString.contains("?") {
            urlString += "?"
        } else {
            urlString += "&"
        }
        urlString += "offset=1"
        urlString += "&pageSize=50"
        urlString += "&fields[]=subject,description,startDate,dueDate,estimatedTime,spentTime,percentageDone,createdAt,updatedAt,lockVersion"
        urlString += "&fields[]=_links"
        
        print("Loading work packages from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL: \(urlString)"
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.trustingSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to load work packages: \(error.localizedDescription)"
                    completion(false)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self.errorMessage = "Failed to load work packages"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let embedded = json["_embedded"] as? [String: Any],
                       let elements = embedded["elements"] as? [[String: Any]] {
                        
                        var newWorkPackages: [WorkPackage] = []
                        
                        for element in elements {
                            if let workPackage = try? JSONDecoder().decode(WorkPackage.self, from: JSONSerialization.data(withJSONObject: element)) {
                                newWorkPackages.append(workPackage)
                            }
                        }
                        
                        self.workPackages = newWorkPackages
                        print("Successfully loaded \(newWorkPackages.count) work packages")
                        completion(true)
                    } else {
                        self.errorMessage = "Invalid response format"
                        completion(false)
                    }
                } catch {
                    self.errorMessage = "Failed to parse work packages: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }.resume()
    }
    
    private func loadMissingProjectDetails(completion: @escaping () -> Void) {
        let projectIds = Set(workPackages.compactMap { extractProjectId(from: $0) })
        let missingProjectIds = projectIds.filter { !projectsDict.keys.contains($0) }
        
        print("Found missing project IDs: \(missingProjectIds)")
        
        guard !missingProjectIds.isEmpty else {
            print("No missing projects to load")
            completion()
            return
        }
        
        let group = DispatchGroup()
        var loadedProjects = 0
        
        for projectId in missingProjectIds {
            group.enter()
            
            let urlString = appState.constructApiUrl(path: "/projects/\(projectId)")
            print("Loading project details from: \(urlString)")
            
            guard let url = URL(string: urlString) else {
                print("Invalid URL for project ID: \(projectId)")
                group.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(appState.accessToken ?? "")", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            print("Sending request for project ID: \(projectId) with token: \(String(describing: appState.accessToken?.prefix(5)))...")
            
            URLSession.trustingSession.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                
                if let error = error {
                    print("Error loading project \(projectId): \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response for project \(projectId)")
                    return
                }
                
                print("Project \(projectId) HTTP status: \(httpResponse.statusCode)")
                
                if let data = data {
                    // Manual JSON parsing
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Extract basic project info
                            if let id = json["id"] as? Int,
                               let name = json["name"] as? String,
                               let identifier = json["identifier"] as? String {
                                
                                print("Successfully extracted project: \(name) (ID: \(id))")
                                
                                // Create a minimal Project object with just the data we need
                                let project = Project(
                                    id: id,
                                    identifier: identifier,
                                    name: name,
                                    active: true,
                                    isPublic: true,
                                    description: nil,
                                    createdAt: "",
                                    updatedAt: "",
                                    statusExplanation: nil,
                                    customField1: nil,
                                    customField2: nil,
                                    customField6: nil,
                                    links: ProjectLinks(
                                        selfLink: Link(href: "", title: nil, templated: nil, method: nil),
                                        createWorkPackage: nil,
                                        createWorkPackageImmediately: nil,
                                        workPackages: nil,
                                        storages: nil,
                                        categories: nil,
                                        versions: nil,
                                        memberships: nil,
                                        types: nil,
                                        update: nil,
                                        updateImmediately: nil,
                                        delete: nil,
                                        schema: nil,
                                        status: nil,
                                        customField1: nil,
                                        customField2: nil,
                                        customField3: nil,
                                        customField6: nil,
                                        ancestors: nil,
                                        projectStorages: nil,
                                        parent: nil
                                    )
                                )
                                
                                DispatchQueue.main.async {
                                    self.projectsDict[projectId] = project
                                    loadedProjects += 1
                                    print("Added project to dictionary: \(name) (ID: \(id))")
                                }
                            } else {
                                print("Missing required fields in project JSON")
                            }
                        } else {
                            print("Invalid JSON format for project \(projectId)")
                        }
                    } catch {
                        print("JSON parsing error: \(error)")
                    }
                } else {
                    print("No data received for project \(projectId)")
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            print("Finished loading projects. Loaded \(loadedProjects) out of \(missingProjectIds.count)")
            print("Final projects dictionary: \(self.projectsDict.map { "\($0.key): \($0.value.name)" }.joined(separator: ", "))")
            completion()
        }
    }
    
    private func loadWorkPackageTypes() {
        guard let token = appState.accessToken else { return }
        
        // Construct the types endpoint URL
        let urlString = appState.constructApiUrl(path: "/types")
        
        print("Constructed types URL: \(urlString)")
        
        guard let url = URL(string: urlString) else { 
            print("Invalid types URL: \(urlString)")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            let workItem = DispatchWorkItem {
                if let error = error {
                    print("Failed to load types: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid HTTP response for types")
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("HTTP Error for types: \(httpResponse.statusCode)")
                    return
                }
                
                guard let data = data else { 
                    print("No data received for types")
                    return 
                }
                
                print("Types data received: \(data.count) bytes")
                
                do {
                    let response = try JSONDecoder().decode(TypeCollection.self, from: data)
                    self.workPackageTypes = response.embedded.elements
                    print("Successfully parsed \(response.embedded.elements.count) work package types")
                } catch {
                    print("Failed to parse types: \(error.localizedDescription)")
                    
                    // Try manual parsing if needed
                    if let responseString = String(data: data, encoding: .utf8) {
                        let previewLength = min(200, responseString.count)
                        let preview = responseString.prefix(previewLength)
                        print("Types response preview: \(preview)...")
                    }
                }
            }
            
            DispatchQueue.main.async(execute: workItem)
        }
        
        task.resume()
    }
    
    private func loadWorkPackageStatuses() {
        guard let token = appState.accessToken else { return }
        
        // Construct the statuses endpoint URL
        let urlString = appState.constructApiUrl(path: "/statuses")
        
        print("Constructed statuses URL: \(urlString)")
        
        guard let url = URL(string: urlString) else { 
            print("Invalid statuses URL: \(urlString)")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            let workItem = DispatchWorkItem {
                if let error = error {
                    print("Failed to load statuses: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid HTTP response for statuses")
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("HTTP Error for statuses: \(httpResponse.statusCode)")
                    return
                }
                
                guard let data = data else { 
                    print("No data received for statuses")
                    return 
                }
                
                print("Statuses data received: \(data.count) bytes")
                
                do {
                    let response = try JSONDecoder().decode(StatusCollection.self, from: data)
                    self.workPackageStatuses = response.embedded.elements
                    print("Successfully parsed \(response.embedded.elements.count) work package statuses")
                } catch {
                    print("Failed to parse statuses: \(error.localizedDescription)")
                    
                    // Try manual parsing if needed
                    if let responseString = String(data: data, encoding: .utf8) {
                        let previewLength = min(200, responseString.count)
                        let preview = responseString.prefix(previewLength)
                        print("Statuses response preview: \(preview)...")
                    }
                }
            }
            
            DispatchQueue.main.async(execute: workItem)
        }
        
        task.resume()
    }
    
    private func loadWorkPackagePriorities() {
        guard let token = appState.accessToken else { return }
        
        // Construct the priorities endpoint URL
        let urlString = appState.constructApiUrl(path: "/priorities")
        
        print("Constructed priorities URL: \(urlString)")
        
        guard let url = URL(string: urlString) else { 
            print("Invalid priorities URL: \(urlString)")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            let workItem = DispatchWorkItem {
                if let error = error {
                    print("Failed to load priorities: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid HTTP response for priorities")
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("HTTP Error for priorities: \(httpResponse.statusCode)")
                    return
                }
                
                guard let data = data else { 
                    print("No data received for priorities")
                    return 
                }
                
                print("Priorities data received: \(data.count) bytes")
                
                do {
                    let response = try JSONDecoder().decode(PriorityCollection.self, from: data)
                    self.workPackagePriorities = response.embedded.elements
                    print("Successfully parsed \(response.embedded.elements.count) work package priorities")
                } catch {
                    print("Failed to parse priorities: \(error.localizedDescription)")
                    
                    // Try manual parsing if needed
                    if let responseString = String(data: data, encoding: .utf8) {
                        let previewLength = min(200, responseString.count)
                        let preview = responseString.prefix(previewLength)
                        print("Priorities response preview: \(preview)...")
                    }
                }
            }
            
            DispatchQueue.main.async(execute: workItem)
        }
        
        task.resume()
    }
    
    private func loadUsers() {
        guard let token = appState.accessToken else {
            return
        }
        
        isLoadingUsers = true
        
        // First try to get project members if this is for a specific project
        guard let project = project else {
            // No project, fallback to generic users endpoint
            loadGenericUsers()
            return
        }
        
        let projectId = project.id
        let urlString = appState.constructApiUrl(path: "/projects/\(projectId)/members")
        
        print("Trying to load project members: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("Invalid project members URL: \(urlString)")
            // Fallback to generic users endpoint
            loadGenericUsers()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                self.parseProjectMembers(data: data)
            } else {
                // If failed, fallback to generic users endpoint
                self.loadGenericUsers()
            }
        }
        
        task.resume()
    }
    
    private func parseProjectMembers(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let embedded = json["_embedded"] as? [String: Any],
               let elements = embedded["elements"] as? [[String: Any]] {
                
                var memberUsers: [User] = []
                
                for element in elements {
                    if let links = element["_links"] as? [String: Any],
                       let principal = links["principal"] as? [String: Any],
                       let href = principal["href"] as? String,
                       let title = principal["title"] as? String {
                        
                        if let userId = href.components(separatedBy: "/").last, let id = Int(userId) {
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
                
                DispatchQueue.main.async {
                    if !memberUsers.isEmpty {
                        self.users = memberUsers
                        print("Successfully extracted \(memberUsers.count) users from project members")
                    } else {
                        // Try generic users endpoint as fallback
                        self.loadGenericUsers()
                    }
                    self.isLoadingUsers = false
                }
            } else {
                DispatchQueue.main.async {
                    // Try generic users endpoint as fallback
                    self.loadGenericUsers()
                }
            }
        } catch {
            print("Error parsing project members: \(error)")
            DispatchQueue.main.async {
                self.loadGenericUsers()
            }
        }
    }
    
    private func loadGenericUsers() {
        guard let token = appState.accessToken else {
            DispatchQueue.main.async {
                self.isLoadingUsers = false
            }
            return
        }
        
        // Construct the users endpoint URL
        let urlString = appState.constructApiUrl(path: "/users")
        
        print("Falling back to generic users URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("Invalid users URL: \(urlString)")
            DispatchQueue.main.async {
                self.isLoadingUsers = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                
                do {
                    let response = try JSONDecoder().decode(UserCollection.self, from: data)
                    self.users = response.embedded.elements
                    print("Successfully parsed \(response.embedded.elements.count) users")
                } catch {
                    print("Failed to decode users: \(error)")
                    self.addCurrentUserAsFallback()
                }
            } else {
                self.addCurrentUserAsFallback()
            }
        }
        
        task.resume()
    }
    
    private func addCurrentUserAsFallback() {
        // Always make sure to add the current user
        if let currentUser = appState.user {
            users = [currentUser]
            print("Using current user as fallback")
        }
    }
}

struct CreateWorkPackageView: View {
    let project: Project
    let types: [WorkPackageType]
    let statuses: [WorkPackageStatus]
    let priorities: [WorkPackagePriority]
    let onWorkPackageCreated: (WorkPackage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    
    @State private var subject: String = ""
    @State private var description: String = ""
    @State private var selectedTypeID: Int?
    @State private var selectedStatusID: Int?
    @State private var selectedPriorityID: Int?
    @State private var startDate: Date = Date()
    @State private var dueDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 7) // One week from now
    @State private var useStartDate: Bool = false
    @State private var useDueDate: Bool = false
    @State private var estimatedHours: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var users: [User] = []
    @State private var isLoadingUsers: Bool = false
    @State private var selectedAssigneeID: Int?
    
    private var defaultTypeID: Int? {
        types.first(where: { $0.isDefault })?.id ?? types.first?.id
    }
    
    private var defaultStatusID: Int? {
        statuses.first(where: { $0.isDefault })?.id ?? statuses.first?.id
    }
    
    private var defaultPriorityID: Int? {
        priorities.first(where: { $0.isDefault })?.id ?? priorities.first?.id
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("General Information")) {
                    TextField("Title", text: $subject)
                        .submitLabel(.next)
                    
                    if selectedTypeID == nil && !types.isEmpty {
                        let _ = { selectedTypeID = defaultTypeID }()
                    }
                    
                    // Type picker
                    Picker("Type", selection: $selectedTypeID) {
                        ForEach(types) { type in
                            Text(type.name).tag(type.id as Int?)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .disabled(types.isEmpty)
                    
                    if selectedStatusID == nil && !statuses.isEmpty {
                        let _ = { selectedStatusID = defaultStatusID }()
                    }
                    
                    // Status picker
                    Picker("Status", selection: $selectedStatusID) {
                        ForEach(statuses) { status in
                            Text(status.name).tag(status.id as Int?)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .disabled(statuses.isEmpty)
                    
                    if selectedPriorityID == nil && !priorities.isEmpty {
                        let _ = { selectedPriorityID = defaultPriorityID }()
                    }
                    
                    // Priority picker
                    Picker("Priority", selection: $selectedPriorityID) {
                        ForEach(priorities) { priority in
                            Text(priority.name).tag(priority.id as Int?)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .disabled(priorities.isEmpty)
                }
                
                Section(header: Text("Description")) {
                    TextEditor(text: $description)
                        .frame(minHeight: 150)
                    
                    Text("The description supports Markdown and basic HTML formatting. For example, use **bold** for bold text, *italic* for italic text, or create lists with - or 1.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                
                Section(header: Text("Dates")) {
                    Toggle("Set start date", isOn: $useStartDate)
                    
                    if useStartDate {
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    }
                    
                    Toggle("Set due date", isOn: $useDueDate)
                    
                    if useDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("Estimation")) {
                    TextField("Estimated hours", text: $estimatedHours)
                        .keyboardType(.decimalPad)
                    
                    Text("Note: This sets the planned hours, not time spent. Time must be logged separately after creation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Work Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createWorkPackage()
                    }
                    .disabled(subject.isEmpty || isSubmitting || selectedTypeID == nil || selectedStatusID == nil || selectedPriorityID == nil)
                }
            }
            .disabled(isSubmitting)
            .overlay(
                Group {
                    if isSubmitting {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                        ProgressView()
                    }
                }
            )
            .onAppear {
                loadUsers()
            }
        }
    }
    
    private func loadUsers() {
        // Fallback to using the API directly since we can't call methods from other structs
        guard let token = appState.accessToken else {
            return
        }
        
        isLoadingUsers = true
        
        // Try to get project members for this project
        let urlString = appState.constructApiUrl(path: "/projects/\(project.id)/members")
        
        guard let url = URL(string: urlString) else {
            self.addCurrentUserAsFallback()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                
                // Process the members data to extract users
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let embedded = json["_embedded"] as? [String: Any],
                       let elements = embedded["elements"] as? [[String: Any]] {
                        
                        var memberUsers: [User] = []
                        
                        for element in elements {
                            if let links = element["_links"] as? [String: Any],
                               let principal = links["principal"] as? [String: Any],
                               let href = principal["href"] as? String,
                               let title = principal["title"] as? String {
                                
                                if let userId = href.components(separatedBy: "/").last, let id = Int(userId) {
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
                        
                        DispatchQueue.main.async {
                            if !memberUsers.isEmpty {
                                self.users = memberUsers
                                print("Successfully extracted \(memberUsers.count) users from project members")
                                self.isLoadingUsers = false
                                return
                            }
                        }
                    }
                } catch {
                    print("Error parsing project members: \(error)")
                }
            }
            
            // If we've reached here, we need to fallback
            DispatchQueue.main.async {
                self.addCurrentUserAsFallback()
            }
        }.resume()
    }
    
    private func addCurrentUserAsFallback() {
        // Always make sure to add the current user
        if let currentUser = appState.user {
            users = [currentUser]
            print("Using current user as fallback for CreateWorkPackageView")
        }
        isLoadingUsers = false
    }
    
    private func createWorkPackage() {
        guard let token = appState.accessToken,
              let typeID = selectedTypeID,
              let statusID = selectedStatusID,
              let priorityID = selectedPriorityID else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        // Create the work package payload
        var workPackageData: [String: Any] = [
            "subject": subject,
            "_links": [
                "project": ["href": "/api/v3/projects/\(project.id)"],
                "type": ["href": "/api/v3/types/\(typeID)"],
                "status": ["href": "/api/v3/statuses/\(statusID)"],
                "priority": ["href": "/api/v3/priorities/\(priorityID)"]
            ]
        ]
        
        // Add assignee if selected
        if let assigneeID = selectedAssigneeID {
            let assigneeDict = ["href": "/api/v3/users/\(assigneeID)"]
            if var links = workPackageData["_links"] as? [String: Any] {
                links["assignee"] = assigneeDict
                workPackageData["_links"] = links
            }
        }
        
        if !description.isEmpty {
            workPackageData["description"] = ["raw": description]
        }
        
        if useStartDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            workPackageData["startDate"] = dateFormatter.string(from: startDate)
        }
        
        if useDueDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            workPackageData["dueDate"] = dateFormatter.string(from: dueDate)
        }
        
        if let estimatedHoursValue = Double(estimatedHours), estimatedHoursValue > 0 {
            // Format as ISO 8601 duration
            let hours = Int(floor(estimatedHoursValue))
            let minutes = Int((estimatedHoursValue - Double(hours)) * 60)
            
            if hours > 0 && minutes > 0 {
                workPackageData["estimatedTime"] = "PT\(hours)H\(minutes)M"
            } else if hours > 0 {
                workPackageData["estimatedTime"] = "PT\(hours)H"
            } else if minutes > 0 {
                workPackageData["estimatedTime"] = "PT\(minutes)M"
            }
        }
        
        // Use the direct work packages endpoint
        let createWorkPackageUrl = appState.constructApiUrl(path: "/work_packages")
        print("Using direct work package creation URL: \(createWorkPackageUrl)")
        
        guard let createUrl = URL(string: createWorkPackageUrl) else {
            errorMessage = "Invalid URL: \(createWorkPackageUrl)"
            isSubmitting = false
            return
        }
        
        var request = URLRequest(url: createUrl)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: workPackageData)
            
            // Debug: Print the JSON body being sent
            if let jsonBody = request.httpBody,
               let jsonString = String(data: jsonBody, encoding: .utf8) {
                print("Creating work package with JSON: \(jsonString)")
            }
            
            let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        isSubmitting = false
                        errorMessage = "Error creating work package: \(error.localizedDescription)"
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("Work package creation HTTP Status Code: \(httpResponse.statusCode)")
                        
                        // Debug: Print response body if available
                        if let data = data,
                           let responseString = String(data: data, encoding: .utf8) {
                            print("Work package creation response: \(responseString)")
                            
                            // Check if this is a form response (validation step)
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let type = json["_type"] as? String,
                               type == "Form",
                               let links = json["_links"] as? [String: Any],
                               let commit = links["commit"] as? [String: Any],
                               let commitHref = commit["href"] as? String {
                                
                                // This is a form response - now we need to make the actual creation request
                                self.submitWorkPackageToCommitUrl(commitHref: commitHref, workPackageData: workPackageData)
                                return
                            }
                        }
                        
                        // Handle direct success or error
                        self.handleWorkPackageCreationResponse(data: data, httpResponse: httpResponse)
                    }
                }
            }
            
            task.resume()
        } catch {
            isSubmitting = false
            errorMessage = "Error encoding work package data: \(error.localizedDescription)"
        }
    }
    
    private func submitWorkPackageToCommitUrl(commitHref: String, workPackageData: [String: Any]) {
        print("Using commit URL from form response: \(commitHref)")
        
        guard let token = appState.accessToken else {
            isSubmitting = false
            errorMessage = "No access token available"
            return
        }
        
        let commitUrl = appState.constructApiUrl(path: commitHref)
        
        guard let url = URL(string: commitUrl) else {
            isSubmitting = false
            errorMessage = "Invalid commit URL: \(commitUrl)"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: workPackageData)
            
            let task = URLSession.trustingSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.isSubmitting = false
                        self.errorMessage = "Error during commit: \(error.localizedDescription)"
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("Work package commit HTTP Status Code: \(httpResponse.statusCode)")
                        
                        // Debug: Print response body if available
                        if let data = data,
                           let responseString = String(data: data, encoding: .utf8) {
                            print("Work package commit response: \(responseString)")
                        }
                        
                        self.handleWorkPackageCreationResponse(data: data, httpResponse: httpResponse)
                    }
                }
            }
            
            task.resume()
        } catch {
            isSubmitting = false
            errorMessage = "Error encoding work package data for commit: \(error.localizedDescription)"
        }
    }
    
    private func handleWorkPackageCreationResponse(data: Data?, httpResponse: HTTPURLResponse) {
        isSubmitting = false
        
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            // Work package created successfully
            if let data = data,
               let workPackage = try? JSONDecoder().decode(WorkPackage.self, from: data) {
                print("Work package created successfully with ID: \(workPackage.id)")
                onWorkPackageCreated(workPackage)
                dismiss()
            } else {
                print("Work package likely created but couldn't parse response")
                // Since we can't parse the response, refresh the work packages list manually
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onWorkPackageCreated(WorkPackage(
                        id: 0,
                        subject: self.subject,
                        description: self.description.isEmpty ? nil : ProjectDescription(
                            format: "markdown",
                            raw: self.description,
                            html: self.description
                        ),
                        startDate: nil,
                        dueDate: nil,
                        estimatedTime: nil,
                        spentTime: nil,
                        percentageDone: nil,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        updatedAt: ISO8601DateFormatter().string(from: Date()),
                        lockVersion: 1,
                        links: WorkPackageLinks(
                            selfLink: Link(href: "", title: nil, templated: nil, method: nil),
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
                    ))
                }
                dismiss()
            }
        } else {
            if let data = data,
               let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                errorMessage = errorResponse.message ?? "Failed to create work package"
                print("Work package creation error: \(errorMessage ?? "Unknown error")")
            } else {
                errorMessage = "Failed to create work package. Status code: \(httpResponse.statusCode)"
                print("Work package creation failed with status code: \(httpResponse.statusCode)")
            }
        }
    }
}

struct WorkPackagesView_Previews: PreviewProvider {
    static var previews: some View {
        let mockProject = Project(
            id: 1,
            identifier: "",
            name: "Sample Project",
            active: true,
            isPublic: true,
            description: nil,
            createdAt: "",
            updatedAt: "",
            statusExplanation: nil,
            customField1: nil,
            customField2: nil,
            customField6: nil,
            links: ProjectLinks(
                selfLink: Link(href: "", title: nil, templated: nil, method: nil),
                createWorkPackage: Link(href: "", title: nil, templated: nil, method: "post"),
                createWorkPackageImmediately: nil,
                workPackages: nil,
                storages: nil,
                categories: nil,
                versions: nil,
                memberships: nil,
                types: nil,
                update: nil,
                updateImmediately: nil,
                delete: nil,
                schema: nil,
                status: nil,
                customField1: nil,
                customField2: nil,
                customField3: nil, 
                customField6: nil,
                ancestors: nil,
                projectStorages: nil,
                parent: nil
            )
        )
        
        return NavigationView {
            WorkPackagesView(project: mockProject)
                .environmentObject(AppState())
        }
    }
} 

