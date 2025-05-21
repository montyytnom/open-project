//
//  KeychainHelper.swift
//  Openproject
//
//  Created by A on 3/18/25.
//

import Foundation
import Security

final class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        let query = [
            kSecValueData: data,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword
        ] as CFDictionary
        
        // Delete existing item if it exists
        SecItemDelete(query)
        
        // Add the new item
        let status = SecItemAdd(query, nil)
        if status != errSecSuccess {
            print("Error saving to Keychain: \(status)")
        }
    }
    
    func read(service: String, account: String) -> Data? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        
        return (status == errSecSuccess) ? (result as? Data) : nil
    }
    
    func delete(service: String, account: String) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword
        ] as CFDictionary
        
        SecItemDelete(query)
    }
}

// Extensions to save and retrieve different types
extension KeychainHelper {
    func save<T>(_ item: T, service: String, account: String) where T: Codable {
        do {
            let data = try JSONEncoder().encode(item)
            save(data, service: service, account: account)
        } catch {
            print("Error encoding: \(error)")
        }
    }
    
    func read<T>(service: String, account: String, type: T.Type) -> T? where T: Codable {
        guard let data = read(service: service, account: account) else { return nil }
        
        do {
            let item = try JSONDecoder().decode(type, from: data)
            return item
        } catch {
            print("Error decoding: \(error)")
            return nil
        }
    }
} 