import Foundation
import Security
import Supabase
import os

/// Routes the SDK's internal logging (warnings/errors only -- .debug/.verbose are
/// per-call tracing and too noisy for a device console) to os.Logger. Without this,
/// `AuthClient.handle(_:)` -- which the app's `.onOpenURL` feeds every OAuth
/// callback through -- catches all failures into `logger?.error(...)` with no
/// logger configured, so a malformed or forged callback produces zero output.
struct MemdoAuthLogger: SupabaseLogger {
    private let logger = Logger(subsystem: "com.memdo.ios", category: "supabase")

    func log(message: SupabaseLogMessage) {
        switch message.level {
        case .error: logger.error("\(message.description)")
        case .warning: logger.warning("\(message.description)")
        case .debug, .verbose: break
        }
    }
}

/// Keychain-backed session storage, same as the SDK's default `KeychainLocalStorage`,
/// except the stored item is `ThisDeviceOnly`: excluded from encrypted backups and
/// never restorable onto a different device. The SDK's own storage hardcodes
/// `kSecAttrAccessibleAfterFirstUnlock` with no way to override it, so this
/// reimplements the same three-method protocol directly against the Keychain.
///
/// Accessibility timing (`AfterFirstUnlock`) is kept identical to the SDK default --
/// only the backup/cross-device behavior changes -- so this doesn't introduce a new
/// "token unavailable while locked" failure mode for any future background refresh.
struct DeviceOnlyKeychainStorage: AuthLocalStorage {
    private let service = "supabase.gotrue.swift"

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func store(key: String, value: Data) throws {
        var addQuery = baseQuery(forKey: key)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = value

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttributes: [String: Any] = [kSecValueData as String: value]
            let updateStatus = SecItemUpdate(
                baseQuery(forKey: key) as CFDictionary,
                updateAttributes as CFDictionary
            )
            try assertSuccess(updateStatus)
        } else {
            try assertSuccess(addStatus)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try assertSuccess(status)
        return result as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status == errSecItemNotFound { return }
        try assertSuccess(status)
    }

    private func assertSuccess(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
