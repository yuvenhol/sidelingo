import KeychainAccess

public protocol KeychainValueStoring: AnyObject {
    func set(_ value: String, key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String) throws
}

private final class KeychainAccessStore: KeychainValueStoring {
    private let keychain: Keychain

    init(service: String, accessibility: Accessibility) {
        keychain = Keychain(service: service).accessibility(accessibility)
    }

    func set(_ value: String, key: String) throws {
        try keychain.set(value, key: key)
    }

    func get(_ key: String) throws -> String? {
        try keychain.get(key)
    }

    func remove(_ key: String) throws {
        try keychain.remove(key)
    }
}

public final class KeychainCredentialStore: ProviderCredentialRepository, @unchecked Sendable {
    public typealias StoreFactory = (String, Accessibility) -> any KeychainValueStoring

    private let store: any KeychainValueStoring

    public convenience init(service: String) {
        self.init(service: service) { service, accessibility in
            KeychainAccessStore(service: service, accessibility: accessibility)
        }
    }

    public init(service: String, makeStore: StoreFactory) {
        store = makeStore(service, .afterFirstUnlockThisDeviceOnly)
    }

    public func credential(for provider: SupportedProvider) throws -> String? {
        try store.get(provider.rawValue)
    }

    public func setCredential(_ credential: String, for provider: SupportedProvider) throws {
        try store.set(credential, key: provider.rawValue)
    }

    public func deleteCredential(for provider: SupportedProvider) throws {
        try store.remove(provider.rawValue)
    }
}
