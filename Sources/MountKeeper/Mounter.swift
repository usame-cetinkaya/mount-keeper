import AppKit
import Network

/// Keeps every share in the store mounted.
///
/// Checks run once a minute, after the Mac wakes and whenever the network
/// comes up. A check does nothing if the share is mounted, nothing if the
/// server doesn't answer, and otherwise mounts it quietly with the password
/// saved in Keychain.
@MainActor
final class Mounter {
    enum Status: Equatable {
        case checking
        case mounting
        case mounted(at: String)
        case unreachable
        case invalid(String)
        case failed(String)
    }

    private(set) var statuses: [String: Status] = [:]
    /// Called on the main actor whenever a status changes.
    var onChange: (() -> Void)?

    private let store: ShareStore
    private var inFlight: Set<String> = []
    private var timer: Timer?
    private var pendingCheck: DispatchWorkItem?
    private let pathMonitor = NWPathMonitor()

    init(store: ShareStore) {
        self.store = store
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAll() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The network usually isn't back yet; the path monitor covers the rest.
            MainActor.assumeIsolated { self?.checkAll(after: 5) }
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMountedStatuses() }
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.checkAll(after: 2) }
        }
        pathMonitor.start(queue: .main)
        checkAll()
    }

    /// Checks every share after `delay` seconds; a later call replaces a pending one.
    func checkAll(after delay: TimeInterval) {
        pendingCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkAll() }
        }
        pendingCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func checkAll() {
        check(store.shares, allowUI: false)
    }

    /// Mounts the given shares if they aren't mounted. With `allowUI`, macOS may
    /// show its sign-in dialog; automatic checks never do.
    func check(_ shares: [String], allowUI: Bool) {
        let mounts = MountTable.networkShares()
        statuses = statuses.filter { store.shares.contains($0.key) }
        for share in shares {
            check(share, mounts: mounts, allowUI: allowUI)
        }
        onChange?()
    }

    private func check(_ share: String, mounts: [MountedShare], allowUI: Bool) {
        let address: ShareAddress
        switch ShareAddress.parse(share) {
        case .failure(let error):
            statuses[share] = .invalid(error.message)
            return
        case .success(let parsed):
            address = parsed
        }
        if let mounted = mounts.first(where: { $0.address == address }) {
            statuses[share] = .mounted(at: mounted.mountPoint)
            return
        }
        guard !inFlight.contains(share),
              let url = ShareAddress.url(from: share),
              let port = ShareAddress.port(for: share) else { return }
        inFlight.insert(share)
        if statuses[share] == nil { statuses[share] = .checking }

        Task {
            let reachable = await Reachability.canConnect(host: address.host, port: port)
            guard store.shares.contains(share) else {
                inFlight.remove(share)
                return
            }
            guard reachable else {
                inFlight.remove(share)
                update(share, .unreachable)
                return
            }
            update(share, .mounting)
            NetworkMount.mount(url, allowUI: allowUI) { error in
                self.inFlight.remove(share)
                guard self.store.shares.contains(share) else { return }
                // The mount table is the source of truth: an "already mounted" error is a success.
                if let mounted = MountTable.networkShares().first(where: { $0.address == address }) {
                    self.update(share, .mounted(at: mounted.mountPoint))
                } else {
                    self.update(share, .failed(error ?? "Mounted, but the share isn't in the mount table."))
                }
            }
        }
    }

    /// Updates statuses after something was mounted or ejected, without mounting anything.
    private func refreshMountedStatuses() {
        let mounts = MountTable.networkShares()
        for share in store.shares where !inFlight.contains(share) {
            guard let address = ShareAddress(url: share) else { continue }
            if let mounted = mounts.first(where: { $0.address == address }) {
                statuses[share] = .mounted(at: mounted.mountPoint)
            } else if case .mounted = statuses[share] {
                statuses[share] = .checking
            }
        }
        onChange?()
    }

    private func update(_ share: String, _ status: Status) {
        statuses[share] = status
        onChange?()
    }
}
