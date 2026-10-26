import AppKit
import ServiceManagement

/// The share list: add and remove shares, mount them now, and turn the login item on or off.
@MainActor
final class SharesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?

    private let store: ShareStore
    private let mounter: Mounter
    private let tableView = ShareTableView()
    private let addRemove = NSSegmentedControl()
    private let mountNowButton = NSButton(title: "Mount Now", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
    private let approvalButton = NSButton(title: "Allow in Login Items…", target: nil, action: nil)

    private enum Column {
        static let path = NSUserInterfaceItemIdentifier("path")
        static let status = NSUserInterfaceItemIdentifier("status")
    }

    init(store: ShareStore, mounter: Mounter) {
        self.store = store
        self.mounter = mounter
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mount Keeper"
        window.minSize = NSSize(width: 480, height: 260)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SharesWindow")
        if !window.setFrameUsingName("SharesWindow") { window.center() }
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func reload() {
        let selection = tableView.selectedRowIndexes
        tableView.reloadData()
        tableView.selectRowIndexes(selection.filteredIndexSet { $0 < store.shares.count }, byExtendingSelection: false)
        updateControls()
    }

    // MARK: - Layout

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        let pathColumn = NSTableColumn(identifier: Column.path)
        pathColumn.title = "Network Path"
        pathColumn.width = 300
        pathColumn.minWidth = 160
        let statusColumn = NSTableColumn(identifier: Column.status)
        statusColumn.title = "Status"
        statusColumn.minWidth = 140
        tableView.addTableColumn(pathColumn)
        tableView.addTableColumn(statusColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openInFinder)
        tableView.onDelete = { [weak self] in self?.removeSelected() }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        addRemove.segmentStyle = .smallSquare
        addRemove.trackingMode = .momentary
        addRemove.segmentCount = 2
        addRemove.setImage(NSImage(named: NSImage.addTemplateName), forSegment: 0)
        addRemove.setImage(NSImage(named: NSImage.removeTemplateName), forSegment: 1)
        addRemove.setToolTip("Add a network share", forSegment: 0)
        addRemove.setToolTip("Stop keeping the selected shares mounted", forSegment: 1)
        addRemove.setWidth(28, forSegment: 0)
        addRemove.setWidth(28, forSegment: 1)
        addRemove.target = self
        addRemove.action = #selector(addRemoveClicked)

        mountNowButton.target = self
        mountNowButton.action = #selector(mountNow)
        mountNowButton.bezelStyle = .rounded
        mountNowButton.toolTip = "Mount the selected shares, or all of them, and ask for a password if Keychain has none"

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLoginItem)
        approvalButton.target = self
        approvalButton.action = #selector(openLoginItemsSettings)
        approvalButton.bezelStyle = .rounded
        approvalButton.controlSize = .small

        let footer = NSTextField(wrappingLabelWithString:
            "Mount Keeper runs in the background. It checks every minute, after the Mac wakes and when the network changes, " +
            "and mounts any share that's missing. Closing this window keeps it running; open Mount Keeper again to change the list.")
        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let controls = NSStackView(views: [addRemove, mountNowButton, spacer, approvalButton, loginCheckbox])
        controls.orientation = .horizontal
        controls.spacing = 10

        let stack = NSStackView(views: [scroll, controls, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    private func updateControls() {
        let hasSelection = !tableView.selectedRowIndexes.isEmpty
        addRemove.setEnabled(hasSelection, forSegment: 1)
        mountNowButton.isEnabled = !store.shares.isEmpty
        mountNowButton.title = hasSelection ? "Mount Selected" : "Mount Now"

        #if DEBUG
        loginCheckbox.isEnabled = false
        loginCheckbox.state = .off
        loginCheckbox.toolTip = "Debug builds don't open at login"
        approvalButton.isHidden = true
        #else
        let status = SMAppService.mainApp.status
        loginCheckbox.state = status == .enabled || status == .requiresApproval ? .on : .off
        approvalButton.isHidden = status != .requiresApproval
        approvalButton.toolTip = "macOS needs your approval in System Settings › General › Login Items"
        #endif
    }

    // MARK: - Actions

    @objc private func addRemoveClicked() {
        if addRemove.selectedSegment == 0 {
            promptForShare(prefill: suggestedShare())
        } else {
            removeSelected()
        }
    }

    /// A mounted network share that isn't in the list yet, so adding the one
    /// you just connected to in Finder takes one click.
    private func suggestedShare() -> String {
        let listed = store.shares.compactMap(ShareAddress.init(url:))
        return MountTable.networkShares().first { !listed.contains($0.address) }?.url ?? "smb://"
    }

    private func promptForShare(prefill: String, error: String? = nil) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Add a network share"
        alert.informativeText = error ??
            "Enter the address you use in Finder's Connect to Server, including the share name."
        if error != nil { alert.alertStyle = .warning }
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: prefill)
        field.placeholderString = "smb://server/share"
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .alertFirstButtonReturn else { return }
                switch self.store.add(field.stringValue) {
                case .failure(let error):
                    // Reopen once the first sheet has gone.
                    DispatchQueue.main.async {
                        self.promptForShare(prefill: field.stringValue, error: error.message)
                    }
                case .success(let share):
                    self.reload()
                    self.mounter.check([share], allowUI: true)
                }
            }
        }
    }

    private func removeSelected() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }
        store.remove(at: rows)
        tableView.deselectAll(nil)
        mounter.checkAll()
        reload()
    }

    @objc private func mountNow() {
        let rows = tableView.selectedRowIndexes
        let shares = rows.isEmpty ? store.shares : rows.map { store.shares[$0] }
        mounter.check(shares, allowUI: true)
    }

    @objc private func openInFinder() {
        let row = tableView.clickedRow
        guard row >= 0, row < store.shares.count,
              case .mounted(let point) = mounter.statuses[store.shares[row]] else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: point))
    }

    @objc private func toggleLoginItem() {
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = loginCheckbox.state == .on
                ? "Mount Keeper couldn't be added to your login items."
                : "Mount Keeper couldn't be removed from your login items."
            if let window { alert.beginSheetModal(for: window) }
        }
        updateControls()
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Window

    func windowDidBecomeKey(_ notification: Notification) {
        updateControls()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.shares.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier)
        let share = store.shares[row]
        if identifier == Column.path {
            cell.textField?.stringValue = share
            cell.textField?.textColor = .labelColor
            cell.toolTip = share
        } else {
            let (text, color) = describe(mounter.statuses[share])
            cell.textField?.attributedStringValue = statusText(text, color: color)
            cell.toolTip = text
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControls()
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func describe(_ status: Mounter.Status?) -> (String, NSColor) {
        switch status {
        case .mounted(let point): return ("Mounted at \(point)", .systemGreen)
        case .mounting: return ("Mounting…", .systemBlue)
        case .checking, nil: return ("Checking…", .tertiaryLabelColor)
        case .unreachable: return ("Server not reachable", .systemOrange)
        case .invalid(let message): return (message, .systemRed)
        case .failed(let message): return (message, .systemRed)
        }
    }

    private func statusText(_ text: String, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
        result.append(NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.labelColor]))
        return result
    }
}

/// Removes the selected shares on Delete or Backspace.
final class ShareTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
