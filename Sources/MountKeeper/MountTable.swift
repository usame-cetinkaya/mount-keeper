import Foundation

/// A network file system that is currently mounted.
struct MountedShare: Sendable {
    let address: ShareAddress
    let mountPoint: String
    /// The share as a URL, e.g. "smb://user@host/share".
    let url: String?
}

enum MountTable {
    /// Network shares in the mount table. Uses `MNT_NOWAIT`, so a server that
    /// went away can't block the call.
    static func networkShares() -> [MountedShare] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        return (0..<Int(count)).compactMap { index in
            var entry = buffer[index]
            let fileSystem = string(from: &entry.f_fstypename)
            let from = string(from: &entry.f_mntfromname)
            guard let address = ShareAddress(fileSystem: fileSystem, mountedFrom: from) else { return nil }
            return MountedShare(
                address: address,
                mountPoint: string(from: &entry.f_mntonname),
                url: ShareAddress.url(fileSystem: fileSystem, mountedFrom: from)
            )
        }
    }

    private static func string<T>(from tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
