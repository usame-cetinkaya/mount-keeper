# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- `scripts/build.sh` - Release build: `dist/Mount Keeper.app` + `.dmg` (Apple Silicon only)
- `CONFIGURATION=debug scripts/build.sh && open "dist/Mount Keeper.app"` - Debug build to run locally (does not register as a login item)
- `swift test` - Unit tests (Swift Testing; needs full Xcode, not just the Command Line Tools)
- `swift scripts/make-icon.swift` - Redraws `Resources/AppIcon.icns`

The app must run from a bundle: `SMAppService` and reopening the window through LaunchServices don't work with `swift run`.

Debug and release builds share the bundle id, so they share the share list in UserDefaults (`defaults read com.usamecetinkaya.mount-keeper`). Status changes are logged under subsystem `com.usamecetinkaya.mount-keeper`.

## Goals

A background app that keeps network shares mounted across sleep and network changes. Keep memory, CPU and release size minimal: AppKit only (no SwiftUI), Apple frameworks only, no third-party packages. No Dock or menu bar icon while running in the background.

## Architecture

- `App.swift` - Entry point; runs `NSApplication` as an accessory app.
- `AppDelegate.swift` - Starts the `Mounter`, registers the login item (`SMAppService.mainApp`) on the first release launch only (afterwards the checkbox decides), and shows the window unless launched as a login item (`keyAELaunchedAsLogInItem`) with shares configured. Reopening the app shows the window; the activation policy is `.regular` while it's open (Dock icon, main menu for Cmd-Q / copy and paste) and `.accessory` again when it closes. `MainMenu` builds that menu.
- `Mounter.swift` - Checks every share once a minute, 5 s after wake, and 2 s after an `NWPathMonitor` change of interfaces or gateways (the monitor also fires after failed mounts, so identical paths are ignored). Mounted (per the mount table) → nothing; TCP probe fails → `unreachable`; else mount. Failed mounts back off 1, 2, 4… 30 min; `check(_:allowUI: true)` (Mount Now, adding a share) ignores and clears the backoff. `inFlight` prevents overlapping attempts per share.
- `NetworkMount.swift` - `NetFSMountURLAsync` into /Volumes with Keychain credentials; `UIOption` `NoUI` for automatic checks, `AllowUI` for Mount Now. Maps NetFS error codes to messages.
- `Reachability.swift` - `NWConnection` TCP probe with a timeout.
- `MountTable.swift` - `getmntinfo(MNT_NOWAIT)` → mounted network shares.
- `ShareAddress.swift` - Parses share URLs and mount table entries (`f_fstypename` + `f_mntfromname`) into a comparable file system / host / path, ignoring user, case, percent-encoding and port in the mount table. Default probe ports per scheme. Covered by tests.
- `ShareStore.swift` - The share URLs as a string array in UserDefaults (`shares`), with validation and duplicate detection.
- `SharesWindowController.swift` - The window: table of shares and statuses, +/− (add sheet prefilled with a mounted share not in the list), Mount Now, Open at login.

## Packaging

`scripts/build.sh` assembles the bundle by hand from `Resources/` (Info.plist with `LSUIElement`, AppIcon.icns), strips and ad-hoc signs it (`CODESIGN_IDENTITY` overrides), and creates an LZMA-compressed DMG. `.github/workflows/release.yml` runs only when a tag like `1.2.3` is pushed, not on other pushes: it tests, builds and publishes a GitHub release with the dmg.
