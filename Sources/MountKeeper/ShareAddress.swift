import Foundation

/// What identifies a network share: its file system, host and share path.
///
/// Used to match a configured share URL against the mount table. User names,
/// letter case, percent-encoding and trailing slashes are ignored, so
/// `smb://me@Server/My%20Share/` and the mount table's `//server/My Share`
/// are the same share.
struct ShareAddress: Equatable, Sendable {
    /// statfs file system name: "smbfs", "afpfs", "nfs" or "webdav".
    let fileSystem: String
    let host: String
    let path: String

    enum ParseError: Error, Equatable {
        case notAURL
        case unsupportedScheme(String)
        case missingHost
        case missingShare

        var message: String {
            switch self {
            case .notAURL:
                return "Enter an address like smb://server/share."
            case .unsupportedScheme(let scheme):
                return "\"\(scheme)\" isn't supported. Use smb, afp, nfs, http or https."
            case .missingHost:
                return "The address needs a server name or IP address, like smb://server/share."
            case .missingShare:
                return "Add the share name after the server, like smb://server/share."
            }
        }
    }

    init(fileSystem: String, host: String, path: String) {
        self.fileSystem = fileSystem
        self.host = host.lowercased()
        self.path = Self.normalize(path: path)
    }

    /// Parses an address the way Finder's Connect to Server accepts it.
    static func parse(_ string: String) -> Result<ShareAddress, ParseError> {
        guard let url = url(from: string), let scheme = url.scheme?.lowercased() else {
            return .failure(.notAURL)
        }
        guard let fileSystem = fileSystem(forScheme: scheme) else {
            return .failure(.unsupportedScheme(scheme))
        }
        guard let host = url.host, !host.isEmpty else { return .failure(.missingHost) }
        let address = ShareAddress(fileSystem: fileSystem, host: host, path: url.path)
        guard !address.path.isEmpty else { return .failure(.missingShare) }
        return .success(address)
    }

    init?(url string: String) {
        guard case .success(let address) = Self.parse(string) else { return nil }
        self = address
    }

    /// Parses a mount table entry (statfs `f_fstypename` and `f_mntfromname`).
    init?(fileSystem: String, mountedFrom from: String) {
        switch fileSystem {
        case "smbfs", "afpfs":
            // "//user@host/share", "//DOMAIN;user@host/share" or "//host/share"
            guard from.hasPrefix("//") else { return nil }
            let rest = from.dropFirst(2)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            var authority = rest[..<slash]
            if let at = authority.lastIndex(of: "@") {
                authority = authority[authority.index(after: at)...]
            }
            let host = Self.stripPort(String(authority))
            self.init(fileSystem: fileSystem, host: host, path: String(rest[slash...]))
        case "nfs":
            // "host:/export/path"
            guard let colon = from.firstIndex(of: ":") else { return nil }
            self.init(fileSystem: fileSystem, host: String(from[..<colon]),
                      path: String(from[from.index(after: colon)...]))
        case "webdav":
            guard let url = URL(string: from), let host = url.host else { return nil }
            self.init(fileSystem: fileSystem, host: host, path: url.path)
        default:
            return nil
        }
        if host.isEmpty || path.isEmpty { return nil }
    }

    /// The URL to show for a mounted share, for example when suggesting it in the add dialog.
    static func url(fileSystem: String, mountedFrom from: String) -> String? {
        switch fileSystem {
        case "smbfs": return from.hasPrefix("//") ? "smb:" + from : nil
        case "afpfs": return from.hasPrefix("//") ? "afp:" + from : nil
        case "nfs":
            guard let colon = from.firstIndex(of: ":") else { return nil }
            return "nfs://" + from[..<colon] + from[from.index(after: colon)...]
        case "webdav": return from
        default: return nil
        }
    }

    /// The TCP port to probe before mounting: the URL's own port, or the protocol's default.
    static func port(for string: String) -> UInt16? {
        guard let url = url(from: string), let scheme = url.scheme?.lowercased() else { return nil }
        if let port = url.port, let value = UInt16(exactly: port) { return value }
        switch scheme {
        case "smb", "cifs": return 445
        case "afp": return 548
        case "nfs": return 2049
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    /// Parses the address, also accepting unencoded spaces and other characters
    /// people type into Connect to Server.
    static func url(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }
        return URL(string: encoded).flatMap { $0.scheme != nil ? $0 : nil }
    }

    private static func fileSystem(forScheme scheme: String) -> String? {
        switch scheme {
        case "smb", "cifs": return "smbfs"
        case "afp": return "afpfs"
        case "nfs": return "nfs"
        case "http", "https": return "webdav"
        default: return nil
        }
    }

    private static func normalize(path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        return decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func stripPort(_ authority: String) -> String {
        guard let colon = authority.lastIndex(of: ":"),
              !authority.contains("]") || authority[..<colon].hasSuffix("]"),
              authority[authority.index(after: colon)...].allSatisfy(\.isNumber) else {
            return authority
        }
        return String(authority[..<colon])
    }
}
