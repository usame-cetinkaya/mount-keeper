import Foundation

/// The share URLs to keep mounted, in the order the user added them.
/// Stored as a string array in UserDefaults under "shares".
@MainActor
final class ShareStore {
    private static let key = "shares"
    private let defaults: UserDefaults

    private(set) var shares: [String] {
        didSet { defaults.set(shares, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shares = defaults.stringArray(forKey: Self.key) ?? []
    }

    enum AddError: Error {
        case invalid(ShareAddress.ParseError)
        case duplicate

        var message: String {
            switch self {
            case .invalid(let error): return error.message
            case .duplicate: return "This share is already in the list."
            }
        }
    }

    /// Adds the share and returns the stored string (trimmed).
    func add(_ string: String) -> Result<String, AddError> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ShareAddress.parse(trimmed) {
        case .failure(let error):
            return .failure(.invalid(error))
        case .success(let address):
            if shares.contains(where: { ShareAddress(url: $0) == address }) {
                return .failure(.duplicate)
            }
            shares.append(trimmed)
            return .success(trimmed)
        }
    }

    func remove(at indexes: IndexSet) {
        shares = shares.enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
    }
}
