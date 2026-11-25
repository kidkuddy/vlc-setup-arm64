# Setup for VLC (arm64)

A native Apple Silicon (arm64) macOS helper that prepares [VLC](https://www.videolan.org/vlc/)
for phone remote-control apps, so no Rosetta is needed.

It is an unofficial, interoperable reimplementation in Swift of an older x86_64-only setup helper.
It is **not affiliated with or endorsed by Hobbyist Software or VideoLAN**. "VLC" is a trademark of
VideoLAN and is used here only to name the app this tool configures.

## What it does

- **Setup VLC**: quits VLC if it is running, then edits `~/Library/Preferences/org.videolan.vlc/vlcrc`
  to enable VLC's web interface: `extraintf=http` and `http-password=<password>`. The default password
  is `vlcremote`, and you can set your own on the Advanced tab. It then checks the macOS firewall and
  relaunches VLC.
- **Bonjour beacon**: while the app is open it advertises `_hs-ident._tcp` on the local network so
  compatible phone apps can find this Mac.
- **Web pairing** (Android and others): requests a pairing passcode from the remote app's pairing
  service and shows when your device has contacted it.
- **Connection help**: opens the remote app's online reachability test with this Mac's IPs and port 8080.

The Bonjour service type, pairing endpoints and test page belong to the existing phone app's
protocol. They are used unchanged so that the phone app keeps working.

Requires macOS 13+ and VLC 2.1 or newer (VLC 3.x recommended).

## Build

```sh
./build.sh        # runs the vlcrc self-check, then builds build/Setup for VLC.app (arm64, ad-hoc signed)
```

Needs Xcode or the Command Line Tools (swiftc). No dependencies.

## Layout

- `Sources/VLCRC.swift`: the vlcrc edit (pure function)
- `Sources/Services.swift`: password storage, Bonjour, VLC control, firewall check, pairing
- `Sources/main.swift`: AppKit UI
- `Tests/main.swift`: self-check for the vlcrc edit
