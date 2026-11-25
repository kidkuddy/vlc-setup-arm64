import Foundation

let vlcrcMarker = "#added by Setup for VLC as could not find the preference elsewhere"

/// Port of -[Worker enableHttpInterface] from the original x86_64 helper.
/// Every `extraintf=` / `#extraintf=` line becomes `extraintf=http`, every
/// `http-password=` / `#http-password=` line gets the password. A key that is
/// missing goes right after its section header ([main] / [lua]) behind the
/// marker comment, or at the end of the file when the section is absent.
func enableHTTPInterface(in text: String, password: String) -> String {
    var lines = text.components(separatedBy: "\n")
    var hasIntf = false, hasPassword = false
    for i in lines.indices {
        let line = lines[i]
        if line.hasPrefix("extraintf=") || line.hasPrefix("#extraintf=") {
            lines[i] = "extraintf=http"; hasIntf = true
        } else if line.hasPrefix("http-password=") || line.hasPrefix("#http-password=") {
            lines[i] = "http-password=\(password)"; hasPassword = true
        }
    }
    func add(_ entry: String, under section: String) {
        if let i = lines.firstIndex(where: { $0.hasPrefix(section) }) {
            lines.insert(contentsOf: [vlcrcMarker, entry], at: i + 1)
        } else {
            lines += [vlcrcMarker, entry]
        }
    }
    if !hasIntf { add("extraintf=http", under: "[main]") }
    if !hasPassword { add("http-password=\(password)", under: "[lua]") }
    return lines.joined(separator: "\n")
}
