import Foundation
import NetFS

enum NetworkMount {
    /// Mounts the share under /Volumes, the way Finder's Connect to Server does.
    ///
    /// Credentials come from the Keychain. With `allowUI`, macOS shows its own
    /// sign-in dialog when none are saved (with a "Remember this password in my
    /// keychain" option); without it, a missing password fails quietly.
    /// Calls `completion` on the main queue with nil on success, or an error message.
    @MainActor
    static func mount(_ url: URL, allowUI: Bool, completion: @escaping @MainActor (String?) -> Void) {
        let openOptions = NSMutableDictionary()
        // kNAUIOptionKey / kNAUIOptionAllowUI / kNAUIOptionNoUI are CFSTR macros Swift can't import.
        openOptions["UIOption"] = allowUI ? "AllowUI" : "NoUI"
        var requestID: AsyncRequestID?
        let status = NetFSMountURLAsync(
            url as CFURL, nil, nil, nil, openOptions, nil, &requestID, DispatchQueue.main
        ) { code, _, _ in
            MainActor.assumeIsolated {
                completion(code == 0 ? nil : message(for: code))
            }
        }
        if status != 0 {
            completion(message(for: status))
        }
    }

    static func message(for code: Int32) -> String {
        switch code {
        case EAUTH, EACCES, EPERM:
            return "Couldn't sign in. Click Mount Now to enter the password and save it in Keychain."
        case ENOENT:
            return "The share wasn't found on the server."
        case EEXIST:
            return "Already mounted."
        case ECANCELED, -128, -6003:
            return "Cancelled."
        case ETIMEDOUT, EHOSTUNREACH, EHOSTDOWN, ENETUNREACH, ECONNREFUSED:
            return "The server didn't respond."
        case let code where code > 0:
            return String(cString: strerror(code)).capitalizedFirst + "."
        default:
            return "Couldn't mount (error \(code)). Click Mount Now to try with a sign-in dialog."
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
