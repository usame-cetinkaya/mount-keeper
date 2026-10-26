import Foundation
import Testing
@testable import MountKeeper

@Suite struct ShareAddressTests {
    @Test func matchesMountTableEntryIgnoringUserCaseAndEncoding() {
        let configured = ShareAddress(url: "smb://usame.cetinkaya@192.168.152.19/EWTO-IT")
        let mounted = ShareAddress(fileSystem: "smbfs", mountedFrom: "//usame.cetinkaya@192.168.152.19/EWTO-IT")
        #expect(configured != nil)
        #expect(configured == mounted)
        #expect(ShareAddress(url: "smb://Server.local/My%20Share/") ==
                ShareAddress(fileSystem: "smbfs", mountedFrom: "//server.local/my share"))
        #expect(ShareAddress(url: "smb://server/My Share") ==
                ShareAddress(fileSystem: "smbfs", mountedFrom: "//DOMAIN;user@SERVER/My%20Share"))
    }

    @Test func differentSharesOnOneServerDontMatch() {
        #expect(ShareAddress(url: "smb://server/one") != ShareAddress(url: "smb://server/two"))
        #expect(ShareAddress(url: "smb://server/one") != ShareAddress(url: "afp://server/one"))
    }

    @Test func parsesOtherFileSystems() {
        #expect(ShareAddress(url: "afp://nas/Time Machine") ==
                ShareAddress(fileSystem: "afpfs", mountedFrom: "//me@nas/Time%20Machine"))
        #expect(ShareAddress(url: "nfs://nas/volume1/media") ==
                ShareAddress(fileSystem: "nfs", mountedFrom: "nas:/volume1/media"))
        #expect(ShareAddress(url: "https://dav.example.com/files") ==
                ShareAddress(fileSystem: "webdav", mountedFrom: "https://dav.example.com/files"))
        #expect(ShareAddress(url: "cifs://server/share") ==
                ShareAddress(fileSystem: "smbfs", mountedFrom: "//server/share"))
    }

    @Test func stripsPortFromMountTableHost() {
        #expect(ShareAddress(fileSystem: "smbfs", mountedFrom: "//user@server:4450/share") ==
                ShareAddress(url: "smb://server:4450/share"))
    }

    @Test func rejectsIncompleteAddresses() {
        #expect(ShareAddress.parse("smb://192.168.152.19") == .failure(.missingShare))
        #expect(ShareAddress.parse("smb://192.168.152.19/") == .failure(.missingShare))
        #expect(ShareAddress.parse("ftp://server/share") == .failure(.unsupportedScheme("ftp")))
        #expect(ShareAddress.parse("server/share") == .failure(.notAURL))
        #expect(ShareAddress.parse("smb:///share") == .failure(.missingHost))
        #expect(ShareAddress(fileSystem: "apfs", mountedFrom: "/dev/disk3s1") == nil)
    }

    @Test func suggestsURLForMountedShare() {
        #expect(ShareAddress.url(fileSystem: "smbfs", mountedFrom: "//usame.cetinkaya@192.168.152.19/EWTO-IT") ==
                "smb://usame.cetinkaya@192.168.152.19/EWTO-IT")
        #expect(ShareAddress.url(fileSystem: "nfs", mountedFrom: "nas:/volume1/media") == "nfs://nas/volume1/media")
    }

    @Test func probesProtocolDefaultPorts() {
        #expect(ShareAddress.port(for: "smb://server/share") == 445)
        #expect(ShareAddress.port(for: "afp://server/share") == 548)
        #expect(ShareAddress.port(for: "nfs://server/export") == 2049)
        #expect(ShareAddress.port(for: "https://server/dav") == 443)
        #expect(ShareAddress.port(for: "smb://server:4450/share") == 4450)
    }
}

@Suite @MainActor struct ShareStoreTests {
    private func makeStore() -> ShareStore {
        let defaults = UserDefaults(suiteName: "MountKeeperTests-\(UUID().uuidString)")!
        return ShareStore(defaults: defaults)
    }

    @Test func addsTrimmedAndRejectsDuplicates() throws {
        let store = makeStore()
        #expect(try store.add("  smb://server/share \n").get() == "smb://server/share")
        guard case .failure(.duplicate) = store.add("smb://me@SERVER/Share/") else {
            Issue.record("expected a duplicate")
            return
        }
        #expect(store.shares == ["smb://server/share"])
    }

    @Test func removesByIndex() {
        let store = makeStore()
        _ = store.add("smb://server/a")
        _ = store.add("smb://server/b")
        _ = store.add("smb://server/c")
        store.remove(at: IndexSet([0, 2]))
        #expect(store.shares == ["smb://server/b"])
    }
}
