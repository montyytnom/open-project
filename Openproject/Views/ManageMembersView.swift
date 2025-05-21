import SwiftUI
import UserNotifications

// Import models directly

// Helper extension for debugging JSON
extension Data {
    func prettyPrintedJSONString() -> String {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8) else {
            return String(data: self, encoding: .utf8) ?? "Invalid JSON data"
        }
        return prettyPrintedString
    }
    
    func printJSONStructure() {
        guard let json = try? JSONSerialization.jsonObject(with: self, options: []) else {
            print("Failed to parse JSON")
            return
        }
        
        func describeStructure(_ object: Any, level: Int = 0) -> String {
            let indent = String(repeating: "  ", count: level)
            
            if let dict = object as? [String: Any] {
                let keys = dict.keys.sorted()
                let content = keys.map { key -> String in
                    let value = dict[key]!
                    if let _ = value as? [String: Any] {
                        return "\(indent)\(key): {\n\(describeStructure(value, level: level + 1))\n\(indent)}"
                    } else if let array = value as? [Any], !array.isEmpty {
                        return "\(indent)\(key): [\n\(describeStructure(array, level: level + 1))\n\(indent)]"
                    } else {
                        return "\(indent)\(key): \(type(of: value))"
                    }
                }.joined(separator: ",\n")
                return content
            } else if let array = object as? [Any] {
                if array.isEmpty {
                    return "\(indent)Empty Array"
                }
                if let first = array.first {
                    return "\(indent)First item of \(array.count) items:\n\(describeStructure(first, level: level + 1))"
                } else {
                    return "\(indent)Empty array"
                }
            } else {
                return "\(indent)\(object)"
            }
        }
        
        print("JSON Structure:")
        print(describeStructure(json))
    }
}

// Model structs for ManageMembersView
struct MembershipCollection: Codable {
    let embedded: MembershipEmbedded
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

struct MembershipEmbedded: Codable {
    let elements: [ProjectMember]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
}

struct ProjectMember: Codable, Identifiable {
    let id: Int
    let roles: [ProjectRole]
    let user: ProjectUser
    
    enum CodingKeys: String, CodingKey {
        case id
        case embedded = "_embedded"
        case links = "_links"
    }
    
    enum EmbeddedKeys: String, CodingKey {
        case roles
    }
    
    enum LinksKeys: String, CodingKey {
        case principal
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode the id
        id = try container.decode(Int.self, forKey: .id)
        
        // Decode the user from _links.principal
        let linksContainer = try container.nestedContainer(keyedBy: LinksKeys.self, forKey: .links)
        user = try linksContainer.decode(ProjectUser.self, forKey: .principal)
        
        // Decode roles from _embedded.roles
        do {
            let embeddedContainer = try container.nestedContainer(keyedBy: EmbeddedKeys.self, forKey: .embedded)
            roles = try embeddedContainer.decode([ProjectRole].self, forKey: .roles)
        } catch {
            print("Error decoding roles: \(error)")
            roles = []
        }
    }
    
    // Add encode method to conform to Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode the id
        try container.encode(id, forKey: .id)
        
        // Encode user (_links.principal)
        var linksContainer = container.nestedContainer(keyedBy: LinksKeys.self, forKey: .links)
        try linksContainer.encode(user, forKey: .principal)
        
        // Encode roles (_embedded.roles)
        var embeddedContainer = container.nestedContainer(keyedBy: EmbeddedKeys.self, forKey: .embedded)
        try embeddedContainer.encode(roles, forKey: .roles)
    }
    
    struct ProjectRole: Codable {
        let name: String
        
        enum CodingKeys: String, CodingKey {
            case name
        }
    }
    
    struct ProjectUser: Codable {
        let name: String
        
        enum CodingKeys: String, CodingKey {
            case name = "title"
        }
    }
}

struct Role: Identifiable, Codable {
    let id: Int
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

struct RoleCollection: Codable {
    let embedded: RoleEmbedded
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

struct RoleEmbedded: Codable {
    let elements: [Role]
    
    enum CodingKeys: String, CodingKey {
        case elements
    }
}

// Remove duplicate User-related models - we'll use the ones from the Models folder

// Remove the MembershipAPIErrorResponse and use the common APIErrorResponse

struct ManageMembersView: View {
    let project: Project
    let currentMembers: [ProjectMember]
    @Binding var isPresented: Bool
    let onMembersUpdated: ([ProjectMember]) -> Void
    
    @EnvironmentObject private var appState: AppState
    @State private var users: [User] = []
    @State private var roles: [Role] = []
    @State private var isLoadingUsers = false
    @State private var isLoadingRoles = false
    @State private var isAddingMember = false
    @State private var selectedUserID: Int?
    @State private var selectedRoleIDs: Set<Int> = []
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            List {
                // Current members section
                Section(header: Text("Current Members")) {
                    if currentMembers.isEmpty {
                        Text("No members assigned")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(currentMembers) { member in
                            HStack {
                                Text(member.user.name)
                                
                                Spacer()
                                
                                if !member.roles.isEmpty {
                                    Text(member.roles.map { $0.name }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button(action: {
                                    removeMember(member)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
                
                // Add new member section
                Section(header: Text("Add New Member")) {
                    if isLoadingUsers {
                        ProgressView("Loading users...")
                    } else if users.filter({ user in
                        !currentMembers.contains { member in
                            member.user.name == user.name
                        }
                    }).isEmpty {
                        Text("All available users are already members of this project")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Picker("Select User", selection: $selectedUserID) {
                            Text("Select a user").tag(nil as Int?)
                            ForEach(users.filter { user in
                                // Filter out users who are already members
                                !currentMembers.contains { member in
                                    member.user.name == user.name
                                }
                            }) { user in
                                Text(user.name).tag(user.id as Int?)
                            }
                        }
                        .disabled(isLoadingUsers)
                        
                        VStack(alignment: .leading) {
                            Text("Select Roles")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            if isLoadingRoles {
                                ProgressView("Loading roles...")
                            } else if roles.isEmpty {
                                Text("No roles available")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                ForEach(roles) { role in
                                    Toggle(role.name, isOn: Binding(
                                        get: { selectedRoleIDs.contains(role.id) },
                                        set: { newValue in
                                            if newValue {
                                                selectedRoleIDs.insert(role.id)
                                            } else {
                                                selectedRoleIDs.remove(role.id)
                                            }
                                        }
                                    ))
                                }
                            }
                        }
                        
                        Button(action: {
                            addNewMember()
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Member")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .disabled(selectedUserID == nil || selectedRoleIDs.isEmpty || isAddingMember)
                        .buttonStyle(BorderedButtonStyle())
                        
                        if isAddingMember {
                            ProgressView("Adding member...")
                                .padding(.vertical, 8)
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Manage Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                loadUsers()
                loadRoles()
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
        
        // Use the principals endpoint which is more reliable for getting available users
        var urlComponents = URLComponents(string: "\(appState.apiBaseURL)/principals")!
        urlComponents.queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "filters", value: "[{\"type\":{\"operator\":\"=\",\"values\":[\"User\"]}}]"),
            URLQueryItem(name: "sortBy", value: "[[\"name\",\"asc\"]]")
        ]
        
        guard let url = urlComponents.url else {
            errorMessage = "Invalid URL format"
            isLoadingUsers = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("Fetching users from principals endpoint: \(url)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingUsers = false
                
                if let error = error {
                    print("Network error while fetching users: \(error)")
                    self.errorMessage = "Error fetching users: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Principals endpoint response code: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                        // Print response for debugging
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("Principals response: \(responseString.prefix(200))...")
                        }
                        
                        do {
                            let userResponse = try JSONDecoder().decode(UserCollection.self, from: data)
                            self.users = userResponse.embedded.elements
                            print("Successfully loaded \(self.users.count) users")
                            
                            // If we got no users but have a current user, use that as fallback
                            if self.users.isEmpty, let currentUser = self.appState.user {
                                self.users = [currentUser]
                                print("Using current user as fallback")
                            }
                        } catch {
                            print("Error decoding users: \(error)")
                            // If decoding fails but we have a current user, use that as fallback
                            if let currentUser = self.appState.user {
                                self.users = [currentUser]
                                print("Using current user as fallback after decode error")
                            } else {
                                self.errorMessage = "Error parsing users response"
                            }
                        }
                    } else {
                        // Handle specific error cases
                        switch httpResponse.statusCode {
                        case 403:
                            print("Permission denied accessing principals endpoint")
                            // Fall back to current user if available
                            if let currentUser = self.appState.user {
                                self.users = [currentUser]
                                print("Using current user as fallback after 403")
                            } else {
                                self.errorMessage = "You don't have permission to view the users list"
                            }
                        case 500:
                            print("Server error accessing principals endpoint")
                            // Fall back to current user if available
                            if let currentUser = self.appState.user {
                                self.users = [currentUser]
                                print("Using current user as fallback after 500")
                            } else {
                                self.errorMessage = "Server error while fetching users. Using current user only."
                            }
                        default:
                            if let currentUser = self.appState.user {
                                self.users = [currentUser]
                                print("Using current user as fallback after \(httpResponse.statusCode)")
                            } else {
                                self.errorMessage = "Failed to fetch users. Status code: \(httpResponse.statusCode)"
                            }
                        }
                    }
                }
            }
        }.resume()
    }
    
    private func loadRoles() {
        isLoadingRoles = true
        
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            isLoadingRoles = false
            return
        }
        
        let rolesEndpoint = "\(appState.apiBaseURL)/roles"
        
        guard let url = URL(string: rolesEndpoint) else {
            errorMessage = "Invalid URL format"
            isLoadingRoles = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingRoles = false
                
                if let error = error {
                    errorMessage = "Error fetching roles: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                        do {
                            let roleResponse = try JSONDecoder().decode(RoleCollection.self, from: data)
                            self.roles = roleResponse.embedded.elements
                            print("Roles loaded successfully: \(self.roles.count) roles")
                        } catch {
                            print("Error decoding roles: \(error)")
                            errorMessage = "Error parsing roles"
                        }
                    } else {
                        errorMessage = "Failed to fetch roles. Status code: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
    
    private func addNewMember() {
        guard let accessToken = appState.accessToken,
              let userID = selectedUserID,
              !selectedRoleIDs.isEmpty else {
            errorMessage = "Please select both a user and at least one role"
            return
        }
        
        isAddingMember = true
        errorMessage = nil
        
        // Use the direct memberships endpoint for creating a new membership
        let membershipsEndpoint = "\(appState.apiBaseURL)/memberships"
        
        guard let url = URL(string: membershipsEndpoint) else {
            errorMessage = "Invalid URL format"
            isAddingMember = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the request body
        var membershipData: [String: Any] = [:]
        
        // Add user link and project link
        membershipData["_links"] = [
            "project": [
                "href": "/api/v3/projects/\(project.id)"
            ],
            "principal": [
                "href": "/api/v3/users/\(userID)"
            ],
            "roles": selectedRoleIDs.map { roleID in
                ["href": "/api/v3/roles/\(roleID)"]
            }
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: membershipData)
            
            // Print the JSON request for debugging
            if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                print("Adding member with JSON: \(jsonString)")
            }
            
            // Print request details for debugging
            print("Request URL: \(url)")
            print("Request Headers: \(request.allHTTPHeaderFields ?? [:])")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isAddingMember = false
                    
                    if let error = error {
                        print("Network error: \(error.localizedDescription)")
                        errorMessage = "Network error: \(error.localizedDescription)"
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("HTTP Status Code: \(httpResponse.statusCode)")
                        print("Response Headers: \(httpResponse.allHeaderFields)")
                        
                        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                            // Member added successfully - reload members
                            loadUpdatedMembers()
                            
                            // Reset selection
                            selectedUserID = nil
                            selectedRoleIDs.removeAll()
                        } else {
                            // Try to parse error response
                            if let data = data {
                                let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                                print("Error response: \(responseString)")
                                
                                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                                    // Check for the specific "user already taken" error
                                    if errorResponse.message?.contains("User has already been taken") == true {
                                        errorMessage = "This user is already a member of the project."
                                        // Reset the user selection
                                        selectedUserID = nil
                                    } else if httpResponse.statusCode == 403 {
                                        errorMessage = "You don't have permission to manage members in this project. Please check your project permissions."
                                    } else if httpResponse.statusCode == 500 {
                                        errorMessage = "Server error while adding member. Please try again later."
                                    } else {
                                        errorMessage = errorResponse.message ?? "Failed to add member"
                                    }
                                } else {
                                    if httpResponse.statusCode == 403 {
                                        errorMessage = "You don't have permission to manage members in this project. Please check your project permissions."
                                    } else if httpResponse.statusCode == 500 {
                                        errorMessage = "Server error while adding member. Please try again later."
                                    } else {
                                        errorMessage = "Failed to add member. Status code: \(httpResponse.statusCode)"
                                    }
                                }
                            } else {
                                if httpResponse.statusCode == 403 {
                                    errorMessage = "You don't have permission to manage members in this project. Please check your project permissions."
                                } else if httpResponse.statusCode == 500 {
                                    errorMessage = "Server error while adding member. Please try again later."
                                } else {
                                    errorMessage = "Failed to add member. Status code: \(httpResponse.statusCode)"
                                }
                            }
                        }
                    }
                }
            }.resume()
        } catch {
            isAddingMember = false
            print("Error encoding member data: \(error)")
            errorMessage = "Error encoding member data: \(error.localizedDescription)"
        }
    }
    
    private func removeMember(_ member: ProjectMember) {
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            return
        }
        
        errorMessage = nil
        
        // The correct endpoint to delete a specific membership
        let membershipsEndpoint = "\(appState.apiBaseURL)/memberships/\(member.id)"
        
        guard let url = URL(string: membershipsEndpoint) else {
            errorMessage = "Invalid URL format"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Error removing member: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        // Member removed successfully - reload members
                        loadUpdatedMembers()
                    } else {
                        errorMessage = "Failed to remove member. Status code: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
    
    private func loadUpdatedMembers() {
        // Fetch the updated list of members
        guard let accessToken = appState.accessToken else {
            errorMessage = "No access token available"
            return
        }
        
        // Use the correct URL format with filters
        let membersEndpoint = "\(appState.apiBaseURL)/memberships?filters=[{\"project\":{\"operator\":\"=\",\"values\":[\"\(project.id)\"]}}]"
        
        guard let url = URL(string: membersEndpoint) else {
            errorMessage = "Invalid URL format"
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Error fetching updated members: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300, let data = data {
                        // Print detailed JSON structure for debugging
                        print("Detailed JSON structure for members:")
                        data.printJSONStructure()
                        
                        do {
                            // Print the raw JSON for debugging
                            if let jsonString = String(data: data, encoding: .utf8) {
                                print("Response JSON: \(String(jsonString.prefix(200)))...")
                            }
                            
                            // Try to manually extract members
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let embedded = json["_embedded"] as? [String: Any],
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
                                    // Update the parent view with the parsed members
                                    onMembersUpdated(parsedMembers)
                                } else {
                                    errorMessage = "Error parsing updated members"
                                }
                            }
                            
                            let membershipCollection = try JSONDecoder().decode(MembershipCollection.self, from: data)
                            let updatedMembers = membershipCollection.embedded.elements
                            print("Members updated successfully: \(updatedMembers.count) members")
                            
                            // Callback to update the parent view
                            onMembersUpdated(updatedMembers)
                        } catch {
                            print("Error decoding updated members: \(error)")
                            errorMessage = "Error parsing updated members: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Failed to fetch updated members. Status code: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
} 