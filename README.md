# Mount Keeper

Keeps network shares mounted on macOS. When you close the lid, change networks or lose the connection, macOS drops SMB shares and doesn't bring them back. Mount Keeper notices and mounts them again, without opening Finder windows or asking for passwords.

It runs in the background with no Dock or menu bar icon, and opens at login. It uses only Apple's built-in frameworks: no third-party dependencies, a download of a few hundred KB.

Requires an Apple Silicon Mac running macOS 13 Ventura or later.

## Features

- Mounts SMB, AFP, NFS and WebDAV shares, using the address you'd type in Finder's **Go > Connect to Server**.
- Checks every minute, after the Mac wakes and whenever the network changes.
- Uses the password saved in your Keychain, so it never stores one itself.
- Skips servers it can't reach (at home, off VPN) quietly, with no "server not found" pop-ups.
- Retries a share that fails to mount after 1, 2, 4… up to 30 minutes, so a wrong saved password can't lock your account on the server.
- Opens at login. That way you don't have to remember to open it every time you restart your computer.

## Installation

1. Download the latest `.dmg` file from the [Releases](https://github.com/usame-cetinkaya/mount-keeper/releases) page, or build it yourself (see [Development](#development)).
2. Double-click it when it is downloaded.
3. Drag the "Mount Keeper.app" icon on to the "Applications" icon.
4. Run it from the macOS Launchpad, or Spotlight (Cmd+Space).

When you run the app you might see a warning like this:

> macOS cannot verify the developer of "Mount Keeper". Are you sure you want to open it?

Here is how to fix it:

1. Click the **Done** (or **Cancel**) button of the warning message.
2. Go to **System Settings > Privacy & Security**.
3. Scroll down to the bottom.
4. Find the message **"Mount Keeper" was blocked...** and click the **Open Anyway** button.

You can also refer to this [Apple Support](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) page for more information.

## Adding a Share

1. Open Mount Keeper. The share list opens.
2. Click **+**. If a network share is already mounted, its address is filled in for you.
3. Enter the address including the share name, for example `smb://192.168.1.10/Projects` or `smb://me@nas.local/Photos`, and click **Add**.
4. If macOS asks for a password, tick **Remember this password in my keychain**. Mount Keeper needs the saved password to mount the share later without asking.

To stop keeping a share mounted, select it and click **−** (or press Delete). This doesn't eject the share.

**Mount Now** mounts the selected shares, or all of them, right away and lets macOS ask for a password. Use it after changing your password on the server. Double-click a mounted share to open it in Finder.

## Running in the Background

Closing the window doesn't quit Mount Keeper. It keeps running in the background with no icon anywhere. Open the app again from Launchpad or Spotlight to show the share list.

Quit it from the **Mount Keeper** menu while the window is open. It starts again at the next login.

To stop it from opening at login, untick **Open at login** in the window, or remove it in **System Settings > General > Login Items**. If macOS asks for approval, click **Allow in Login Items…** in the window.

## Troubleshooting

Each status change is logged. To see why a share isn't mounting, open Console and filter by `com.usamecetinkaya.mount-keeper`, or run:

```bash
log show --predicate 'subsystem == "com.usamecetinkaya.mount-keeper"' --last 1h
```

If a share keeps showing "Couldn't sign in", click **Mount Now** and save the password in Keychain when asked.

## Development

- `scripts/build.sh` builds a release `dist/Mount Keeper.app` and `.dmg`.
- `CONFIGURATION=debug scripts/build.sh && open "dist/Mount Keeper.app"` builds a debug app to run locally. It doesn't register as a login item.
- `swift test` runs the unit tests.
- `swift scripts/make-icon.swift` redraws `Resources/AppIcon.icns`.

Pushing a tag like `1.2.3` publishes a GitHub release with the `.dmg`.
