// Self-check for enableHTTPInterface. Built and run by build.sh; exits non-zero on failure.

// VLC 3 layout: both keys present but commented out.
let vlc3 = """
[core] # core program
#extraintf=
[lua] # Lua interface
#http-password=
#http-port=8080
"""
let out1 = enableHTTPInterface(in: vlc3, password: "pw").components(separatedBy: "\n")
assert(out1 == ["[core] # core program", "extraintf=http", "[lua] # Lua interface", "http-password=pw", "#http-port=8080"], "\(out1)")

// Already configured: unchanged apart from the password value.
let configured = "extraintf=http\nhttp-password=old"
assert(enableHTTPInterface(in: configured, password: "new") == "extraintf=http\nhttp-password=new")

// Keys missing: inserted under their section headers behind the marker.
let sparse = "[main] # main program\nfoo=1\n[lua]\nbar=2"
let out2 = enableHTTPInterface(in: sparse, password: "vlcremote").components(separatedBy: "\n")
assert(out2 == ["[main] # main program", vlcrcMarker, "extraintf=http", "foo=1",
                "[lua]", vlcrcMarker, "http-password=vlcremote", "bar=2"], "\(out2)")

// Sections missing: appended at the end (the bundled template has no [lua]).
let template = "[main] # main program\nextraintf=http"
let out3 = enableHTTPInterface(in: template, password: "vlcremote").components(separatedBy: "\n")
assert(out3 == ["[main] # main program", "extraintf=http", vlcrcMarker, "http-password=vlcremote"], "\(out3)")

print("vlcrc check: ok")
