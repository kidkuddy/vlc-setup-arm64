# Setup for VLC

A small macOS app that sets up [VLC](https://www.videolan.org/vlc/) so a phone remote-control
app can control it.

## Features

- **Setup VLC**: turns on VLC's web interface (`extraintf=http`) and sets its password
  (`http-password`) in `~/Library/Preferences/org.videolan.vlc/vlcrc`, quitting and relaunching
  VLC as needed. It also warns if the macOS firewall blocks VLC.
- **Password**: the default is `vlcremote`; set your own on the Advanced tab.
- **Bonjour**: while open, advertises this Mac on the local network so the phone app finds it.
- **Web pairing**: for phones that can't use Bonjour, shows a passcode to enter on the phone.
- **Connection help**: opens an online test that checks your phone can reach this Mac.

Requires macOS 13+ on Apple Silicon and VLC 2.1 or newer.

## Build

```sh
./build.sh
```

Runs the self-check and builds `build/Setup for VLC.app`. Needs Xcode or the Command Line Tools.
