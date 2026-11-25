import AppKit
import SystemConfiguration

// MARK: - Password

enum Access {
    static let defaultPassword = "vlcremote"
    private static let d = UserDefaults.standard

    static var usePassword: Bool {
        get { d.bool(forKey: "HS_VLCRemoteUsePassword") }
        set { d.set(newValue, forKey: "HS_VLCRemoteUsePassword") }
    }
    static var storedPassword: String? { d.string(forKey: "HS_VLCRemoteStoredPassword") }
    static var password: String { usePassword ? (storedPassword ?? defaultPassword) : defaultPassword }
    static func setPassword(_ p: String) {
        d.set(p.isEmpty ? defaultPassword : p, forKey: "HS_VLCRemoteStoredPassword")
    }
    static var passwordIsDefault: Bool { (storedPassword ?? defaultPassword) == defaultPassword }
}

// MARK: - Bonjour beacon the phone app looks for

final class Beacon {
    private let service = NetService(domain: "local.", type: "_hs-ident._tcp.", name: "", port: 1)

    init() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "helperVersion": Data(bundleVersion.utf8),
            "platform": Data("mac,\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)".utf8),
        ]))
        service.publish()
    }
}

var bundleVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "12" }

// MARK: - VLC install + preferences

enum VLC {
    static let bundleID = "org.videolan.vlc"
    static let defaultPath = "/Applications/VLC.app"
    static var chosenPath: String?   // set by File > Select VLC App

    static func locate() -> String? {
        let fm = FileManager.default
        if let p = chosenPath, fm.fileExists(atPath: p) { return p }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           !url.path.contains("VLCStreamer.app") { return url.path }
        return fm.fileExists(atPath: defaultPath) ? defaultPath : nil
    }

    /// 1.0 / 2.0 / 2.1, decided by which web-interface files the VLC bundle ships.
    static func version(at path: String) -> Float {
        let fm = FileManager.default
        if fm.fileExists(atPath: path + "/Contents/MacOS/share/http") { return 1.0 }
        return fm.fileExists(atPath: path + "/Contents/MacOS/share/lua/http/.hosts") ? 2.0 : 2.1
    }

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    static func quit() async -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        for _ in 0..<20 where isRunning { try? await Task.sleep(nanoseconds: 500_000_000) }
        return !isRunning
    }

    static func launch(_ path: String) async -> Bool {
        let cfg = NSWorkspace.OpenConfiguration()
        _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
        for _ in 0..<20 where !isRunning { try? await Task.sleep(nanoseconds: 500_000_000) }
        return isRunning
    }

    static let prefsDir = NSString(string: "~/Library/Preferences/org.videolan.vlc").expandingTildeInPath
    static let prefsFile = prefsDir + "/vlcrc"
    static let oldPrefsFile = NSString(string: "~/Library/Preferences/VLC/vlcrc").expandingTildeInPath

    /// Reads vlcrc, enables the web interface and writes it back. Missing prefs start from the bundled template.
    static func enableHTTP(password: String) throws {
        let fm = FileManager.default
        let source = [prefsFile, oldPrefsFile].first(where: fm.fileExists(atPath:))
        let text: String
        if let source {
            text = try String(contentsOfFile: source, encoding: .utf8)
        } else {
            let template = Bundle.main.path(forResource: "vlcrc", ofType: nil)!
            text = try String(contentsOfFile: template, encoding: .utf8)
        }
        let updated = Data(enableHTTPInterface(in: text, password: password).utf8)
        try fm.createDirectory(atPath: prefsDir, withIntermediateDirectories: true)
        try updated.write(to: URL(fileURLWithPath: prefsFile), options: .atomic)
        if fm.fileExists(atPath: oldPrefsFile) {
            try updated.write(to: URL(fileURLWithPath: oldPrefsFile), options: .atomic)
        }
    }
}

// MARK: - Firewall (via socketfilterfw)

enum Firewall {
    private static func fw(_ args: String...) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        p.arguments = args
        p.standardOutput = out
        p.standardError = out
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// nil when VLC can accept incoming connections, otherwise an explanation for the user.
    static func problem(vlcPath: String) -> String? {
        guard fw("--getglobalstate").contains("enabled") else { return nil }
        if fw("--getblockall").contains("set to enabled") {
            return "Your firewall is set to block all incoming connections. This will stop your iPhone from communicating with VLC.\n\nTurn off 'Block all incoming connections' in the firewall settings."
        }
        let app = fw("--getappblocked", vlcPath)
        if app.contains("permitted") { return nil }
        if app.contains("blocked") {
            return "Your firewall is set to block incoming connections to VLC.\n\nPlease set VLC to 'Allow incoming connections' in the firewall settings."
        }
        if fw("--getallowsigned").contains("ENABLED") { return nil }   // signed VLC is allowed automatically
        return "Your firewall is on, however VLC has not been granted access.\n\nPlease launch VLC, then when you are asked if VLC should be allowed to accept incoming connections, click on the 'Allow' button."
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

// MARK: - Network info

enum Net {
    /// IPv4 addresses per BSD interface name, loopback excluded.
    static func ipv4() -> [(iface: String, ip: String)] {
        var result: [(String, String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var cur = head
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("lo") { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((name, String(cString: host)))
            }
        }
        return result
    }

    /// Private-range addresses, sorted, comma separated.
    static var privateIPv4String: String {
        ipv4().map(\.ip).filter { $0.hasPrefix("192.") || $0.hasPrefix("10.") || $0.hasPrefix("172.") }
            .sorted().joined(separator: ",")
    }

    static var computerName: String { (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac" }

    /// Query escaping that also escapes ;/?:@&=+$,
    static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ";/?:@&=+$,"))) ?? s
    }

    /// Opens the online reachability test with this Mac's IPs and port 8080.
    static func openConnectionHelp() {
        let names = Dictionary((SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).compactMap { i -> (String, String)? in
            guard let bsd = SCNetworkInterfaceGetBSDName(i) as String? else { return nil }
            return (bsd, SCNetworkInterfaceGetLocalizedDisplayName(i) as String? ?? bsd)
        }, uniquingKeysWith: { a, _ in a })
        let addrs = ipv4()
        let ips = addrs.map(\.ip).joined(separator: ",")
        let ifaces = addrs.map { esc("\(names[$0.iface] ?? $0.iface) (\($0.iface))") }.joined(separator: ",")
        if let url = URL(string: "https://hobbyistsoftware.com/vlcremote-test?ips=\(ips)&interfaces=\(ifaces)&port=8080") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Web pairing

final class Pairing {
    private(set) var passcode = ""
    private(set) var requestSent = false
    private(set) var deviceContacted = false
    private(set) var stoppedChecking = false
    private var checks = 0, lastCheck = Date.distantPast, inFlight = false
    private var timer: Timer?
    var onChange: (() -> Void)?

    func start() {
        stop()
        passcode = String(Int.random(in: 0..<10_000))
        requestSent = false; deviceContacted = false; stoppedChecking = false
        checks = 0; lastCheck = .distantPast
        let url = "https://pair.hobbyistsoftware.com/pair/create?local_ip=\(Net.esc(Net.privateIPv4String))&app=vlcRemote&passcode=\(passcode)&local_name=\(Net.esc(Net.computerName))"
        get(url) { body in self.requestSent = Int(body).map(String.init) == body }   // server answers with a number
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        if !deviceContacted { poll() }
        onChange?()
    }

    /// At most 30 checks per passcode, at least 10 s apart.
    private func poll() {
        guard !inFlight else { return }
        if checks >= 30 { stoppedChecking = true; return }
        guard Date().timeIntervalSince(lastCheck) > 10 else { return }
        lastCheck = Date(); checks += 1
        get("https://pair2.hobbyistsoftware.com/pair/check_status?app=vlcRemote&passcode=\(passcode)&v=a\(bundleVersion)") { body in
            self.deviceContacted = body == "checked"
        }
    }

    private func get(_ s: String, _ done: @escaping (String) -> Void) {
        guard let url = URL(string: s) else { return }
        inFlight = true
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 30)) { data, _, _ in
            let body = data.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            DispatchQueue.main.async { self.inFlight = false; done(body); self.onChange?() }
        }.resume()
    }
}
