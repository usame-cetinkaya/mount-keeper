import Foundation
import Network
import os

enum Reachability {
    /// Whether a TCP connection to the server opens within `timeout` seconds.
    /// Checked before mounting, so an unreachable server (at home, off VPN)
    /// fails quietly instead of waiting for the mount to time out.
    static func canConnect(host: String, port: UInt16, timeout: TimeInterval = 3) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Bool) -> Void = { result in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
