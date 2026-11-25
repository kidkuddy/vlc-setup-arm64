import AppKit

// Setup for VLC: native arm64 helper that prepares VLC for phone remote-control apps.
// Unofficial, interoperable reimplementation of an x86-only setup helper; not affiliated with
// Hobbyist Software or VideoLAN.
// ponytail: dropped Sparkle (updates from the x86 feed), Crashlytics/Fabric (dead service),
// CocoaLumberjack, and the VLC < 2.1 paths (.hosts / status.xml via authopen). No VLC that old
// runs on Apple Silicon; on VLC >= 2.1 the original only edits vlcrc, which is what this does.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var beacon: Beacon?
    let pairing = Pairing()

    // UIController outlets
    let deviceLabel = label("", bold: true)
    let webPairingButton = NSButton(title: "Run web pairing helper", target: nil, action: #selector(showPairing))
    let passwordCheckbox = NSButton(checkboxWithTitle: "Use custom password", target: nil, action: #selector(togglePassword))
    let passwordField = NSTextField(string: "")
    let passwordButton = NSButton(title: "Save new password", target: nil, action: #selector(savePassword))
    let defaultPasswordLabel = label("(Default password is 'vlcremote')")
    let progressText = label("")
    var progressSheet: NSWindow?
    var pairingSheet: NSWindow?
    let passcodeLabel = label("")
    let requestImage = NSImageView(), contactImage = NSImageView()
    let stoppedLabel = label("(stopped checking)")

    func applicationDidFinishLaunching(_ n: Notification) {
        beacon = Beacon()
        buildMenu()
        buildWindow()
        updatePasswordUI()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ n: Notification) { if (n.object as? NSWindow) == window { NSApp.terminate(nil) } }

    // MARK: Layout (labels and actions from MainMenu.nib)

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 686, height: 484),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Setup for VLC"
        window.delegate = self

        let segment = NSSegmentedControl(labels: ["iPhone / iPad", "Android / Windows Phone / Web OS"],
                                         trackingMode: .selectOne, target: self, action: #selector(deviceChanged(_:)))
        segment.selectedSegment = 0
        for b in [webPairingButton, passwordCheckbox, passwordButton] { b.target = self }
        deviceChanged(segment)

        let standard = column([
            label("1) Setup", bold: true),
            label("Click the setup button to configure VLC for remote control."),
            NSButton(title: "Setup VLC", target: self, action: #selector(setupVLC)),
            spacer(),
            label("2) Pairing", bold: true),
            label("What kind of phone/tablet are you using?"),
            segment, deviceLabel, webPairingButton,
            spacer(),
            label("3) Help", bold: true),
            NSButton(title: "Connection help", target: self, action: #selector(connectionHelp)),
        ])
        passwordField.placeholderString = "password"
        passwordField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        passwordField.target = self
        passwordField.action = #selector(savePassword)
        let advanced = column([
            label("Set password", bold: true),
            row([passwordCheckbox, passwordField, passwordButton]),
            defaultPasswordLabel,
        ])

        let tabs = NSTabView()
        for (title, view) in [("Standard", standard), ("Advanced", advanced)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        let version = label("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (arm64)")
        version.textColor = .secondaryLabelColor
        let root = column([tabs, version])
        root.alignment = .centerX
        tabs.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title); items.forEach(m.addItem)
            let host = NSMenuItem(); host.submenu = m; main.addItem(host)
        }
        sub("Setup for VLC", [NSMenuItem(title: "Quit Setup for VLC", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")])
        sub("File", [NSMenuItem(title: "Select VLC App…", action: #selector(pickVLC), keyEquivalent: "o")])
        sub("Edit", [
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        let host = NSMenuItem(); host.submenu = windowMenu; main.addItem(host)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    // MARK: Actions

    @objc func deviceChanged(_ s: NSSegmentedControl) {
        let iPhone = s.selectedSegment == 0
        deviceLabel.stringValue = iPhone ? "Your iPhone should spot VLC by the magic of Bonjour!" : "Please run the web pairing helper"
        webPairingButton.isHidden = iPhone
    }

    @objc func setupVLC() { Task { await configure() } }

    @objc func connectionHelp() { Net.openConnectionHelp() }

    @objc func pickVLC() {
        let panel = NSOpenPanel()
        panel.title = "Show us where you have installed VLC"
        panel.message = "Select VLC (wherever it is)"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        VLC.chosenPath = url.path
        alert("VLC Selected", "You have chosen the VLC app to work on. Just click on the setup button to set it up!")
        updatePasswordUI()
    }

    @objc func togglePassword() {
        Access.usePassword = passwordCheckbox.state == .on
        if !Access.usePassword || Access.passwordIsDefault { setupVLC() }
        updatePasswordUI()
    }

    @objc func savePassword() {
        Access.setPassword(passwordField.stringValue)
        setupVLC()
    }

    func updatePasswordUI() {
        let custom = Access.usePassword
        passwordCheckbox.state = custom ? .on : .off
        passwordField.isHidden = !custom
        passwordButton.isHidden = !custom
        defaultPasswordLabel.isHidden = custom
        passwordField.stringValue = Access.password
    }

    // MARK: -[Worker configureAllowingInternetAccess:]

    func configure() async {
        guard let vlc = VLC.locate() else {
            if alert("Setup Failed!", "The system couldn't find VLC. Is it installed?\n\nIf VLC is installed, then please check that it is in the Applications folder.\n\nAlternatively, use 'menu/File/Select VLC App' to specify the location",
                     ["Download VLC", "Close"]) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://www.videolan.org/vlc/")!)
            }
            return
        }
        if !vlc.hasPrefix("/Applications/"),
           alert("Is this the VLC you expected?", "The system has found VLC at:\n\n\(vlc)\n\nwhich isn't the normal location. You can specify which VLC copy to work with in menu/File/Select VLC App",
                 ["Select the correct VLC app", "Continue anyway"]) == .alertFirstButtonReturn {
            pickVLC(); return
        }
        if VLC.version(at: vlc) < 2.1 {
            alert("Setup Failed!", "This copy of VLC is too old for this helper. Please install the current VLC from videolan.org.")
            return
        }
        if VLC.isRunning {
            guard alert("Need to quit VLC", "Setup needs to close VLC in order to continue", ["Quit VLC", "Cancel"]) == .alertFirstButtonReturn else { return }
            showProgress("Quitting VLC\n\nIf VLC doesn't quit automatically, then you may need to use 'Force Quit' to stop it manually.")
            let quit = await VLC.quit()
            hideProgress()
            guard quit else {
                alert("Setup Failed!", "VLC is currently running, please quit VLC and try again.\n(tap on VLC in the dock, then use menu/VLC/quit VLC)")
                return
            }
        }
        do {
            try VLC.enableHTTP(password: Access.password)
        } catch {
            alert("Setup Failed!", "Problem saving prefs when enabling http interface\n\n\(error.localizedDescription)")
            return
        }
        if let problem = Firewall.problem(vlcPath: vlc) {
            alert("Firewall Problem", problem + "\n\nPlease update your firewall settings and then run the helper again.")
            Firewall.openSettings()
            return
        }
        alert("Setup Completed", "VLC is ready for remote control.")
        showProgress("Launching VLC")
        let launched = await VLC.launch(vlc)
        hideProgress()
        if !launched {
            alert("Unable to Launch", "We couldn't launch VLC. Please check that you have installed it by dragging the app to your Applications Folder")
        }
    }

    // MARK: Sheets

    func showProgress(_ text: String) {
        progressText.stringValue = text
        if progressSheet == nil {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.startAnimation(nil)
            progressSheet = sheet(596, 154, row([progressText, spinner]))
        }
        window.beginSheet(progressSheet!)
    }

    func hideProgress() { if let s = progressSheet { window.endSheet(s) } }

    @objc func showPairing() {
        if !VLC.isRunning, let vlc = VLC.locate() { Task { _ = await VLC.launch(vlc) } }
        if pairingSheet == nil {
            passcodeLabel.font = .boldSystemFont(ofSize: 28)
            stoppedLabel.textColor = .secondaryLabelColor
            pairingSheet = sheet(686, 360, column([
                label("Connect using the Web Pairing Helper", bold: true),
                label("Enter this passcode in the pairing page on your phone or tablet."),
                row([label("Passcode:", bold: true), passcodeLabel]),
                row([requestImage, label("Pairing request sent to server")]),
                row([contactImage, label("Device has contacted server"), stoppedLabel]),
                NSButton(title: "Close", target: self, action: #selector(closePairing)),
            ]))
            pairing.onChange = { [weak self] in self?.updatePairing() }
        }
        pairing.start()
        updatePairing()
        window.beginSheet(pairingSheet!)
    }

    @objc func closePairing() {
        pairing.stop()
        if let s = pairingSheet { window.endSheet(s) }
    }

    func updatePairing() {
        passcodeLabel.stringValue = pairing.passcode
        requestImage.image = statusImage(pairing.requestSent)
        contactImage.image = statusImage(pairing.deviceContacted)
        stoppedLabel.isHidden = !pairing.stoppedChecking || pairing.deviceContacted
    }
}

// MARK: - Small AppKit helpers

@MainActor func statusImage(_ ok: Bool) -> NSImage? {
    let img = NSImage(systemSymbolName: ok ? "checkmark.circle.fill" : "xmark.circle.fill", accessibilityDescription: ok ? "done" : "not yet")
    return img?.withSymbolConfiguration(.init(paletteColors: [ok ? .systemGreen : .systemRed]))
}

@MainActor func label(_ s: String, bold: Bool = false) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: s)
    if bold { l.font = .boldSystemFont(ofSize: NSFont.systemFontSize) }
    return l
}

@MainActor func column(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = 8
    s.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    return s
}

@MainActor func row(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .centerY
    return s
}

@MainActor func spacer() -> NSView {
    let v = NSView()
    v.heightAnchor.constraint(equalToConstant: 8).isActive = true
    return v
}

@MainActor func sheet(_ w: CGFloat, _ h: CGFloat, _ content: NSView) -> NSWindow {
    let s = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.titled], backing: .buffered, defer: false)
    s.contentView = content
    return s
}

@MainActor @discardableResult
func alert(_ title: String, _ text: String, _ buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    buttons.forEach { a.addButton(withTitle: $0) }
    return a.runModal()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
