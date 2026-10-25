import CryptoKit
import Foundation
import Security

struct ReportCredential: Codable, Equatable, Sendable {
    let id: UUID
    let token: String

    func validate() throws {
        guard (32...256).contains(token.utf8.count),
              token.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte)
                      || (97...122).contains(byte) || byte == 45 || byte == 95
              }) else { throw ReportCredentialError.invalidCredential }
    }
}

enum ReportCredentialError: Error, LocalizedError, Sendable {
    case invalidOrigin
    case invalidCredential
    case identityConflict
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidOrigin: String(localized: "리포트 서버 주소를 확인해 주세요.")
        case .invalidCredential, .identityConflict, .keychain:
            String(localized: "이 기기의 리포트 연결 정보를 읽거나 저장하지 못했어요. 기존 정보는 유지됩니다.")
        }
    }
}

enum ReportOrigin {
    static func canonical(_ origin: String) throws -> String {
        guard origin.utf8.count <= 2_048, let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !components.path.split(separator: "/").contains("..") else {
            throw ReportCredentialError.invalidOrigin
        }
        if scheme != "https" {
            #if DEBUG
            guard ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) else {
                throw ReportCredentialError.invalidOrigin
            }
            #else
            throw ReportCredentialError.invalidOrigin
            #endif
        }
        var canonical = URLComponents()
        canonical.scheme = scheme
        canonical.host = host
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        canonical.percentEncodedPath = path
        if let port = components.port,
           !((scheme == "https" && port == 443) || (scheme == "http" && port == 80)) {
            guard (1...65_535).contains(port) else { throw ReportCredentialError.invalidOrigin }
            canonical.port = port
        }
        guard let value = canonical.url?.absoluteString, value.utf8.count <= 2_048 else {
            throw ReportCredentialError.invalidOrigin
        }
        return value
    }

    static func key(_ origin: String) throws -> String {
        SHA256.hash(data: Data(try canonical(origin).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ReportCredentials: Sendable {
    private let service: String

    init(service: String? = nil) {
        var defaultService = "dev.repick.health-report-installation"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-use-store") {
            defaultService += ".ui-testing"
        }
        #endif
        self.service = service ?? defaultService
    }

    func read(origin: String) throws -> ReportCredential? {
        var query = try query(origin: origin)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReportCredentialError.keychain(status) }
        guard let data = result as? Data, data.count <= 2_048 else {
            throw ReportCredentialError.invalidCredential
        }
        let credential = try JSONDecoder().decode(ReportCredential.self, from: data)
        try credential.validate()
        return credential
    }

    func save(_ credential: ReportCredential, origin: String) throws {
        try credential.validate()
        let query = try query(origin: origin)
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credential),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query.merging(values) { _, value in value } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard try read(origin: origin) == credential else { throw ReportCredentialError.identityConflict }
            return
        }
        guard status == errSecSuccess else { throw ReportCredentialError.keychain(status) }
    }

    func remove(origin: String) throws {
        let status = SecItemDelete(try query(origin: origin) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ReportCredentialError.keychain(status)
        }
    }

    private func query(origin: String) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: try ReportOrigin.key(origin),
         kSecAttrSynchronizable as String: false]
    }
}
