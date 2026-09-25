# Installing LlamaScope 0.9.1 on macOS

This build is **signed with a Developer ID and notarized**. The
downloaded image opens on a double click, with no warnings and nothing
to work around.

An earlier version of this document explained how to get past the
system's warning. Those instructions are obsolete and have been
removed — not kept "just in case", because an instruction for turning
off a security check goes on to live a life of its own.

The trust this page used to ask for has only partly changed. Apple now
vouches for **who** built this file and that nobody altered it on the
way. It does not vouch for **what** the file does — and LlamaScope
reads your Ollama server log, and with the proxy switched on it sees
the contents of your prompts (what it records out of them is described
in the [README](README.md), section *Privacy*). Route A below is still
the only one that asks you to take nothing on our word.

---

## Route A: build it from source

You build from code you can read. Requires Xcode, not just the
command-line tools.

```sh
git clone https://github.com/MarcinSNowak/llamascope.git
cd llamascope/app
xcodebuild -scheme LlamaScope -configuration Release build
```

The finished bundle sits in the directory `xcodebuild` prints at the
end — the path ends in `Build/Products/Release/LlamaScope.app`. Drag it
to `/Applications` and run it.

If you want to check the README's claim about the proxy yourself — that
the app contains not one byte of its code — this is the moment:

```sh
nm LlamaScope.app/Contents/MacOS/LlamaScope | grep -c ProxyCore   # should print 0
nm LlamaScope.app/Contents/MacOS/LlamaScopeProxy | grep -c ProxyCore
```

## Route B: the ready-made `.dmg`

Download `LlamaScope-0.9.1.dmg` from
[Releases](https://github.com/MarcinSNowak/llamascope/releases), open
it and drag the app to `/Applications`. That is all.

**Apple Silicon only.** On an Intel Mac the system will refuse to open
it, and it will be right: the app would show a panel whose GPU readings
mean nothing there — and that is exactly the kind of calm zero
LlamaScope exists to catch, not to produce. The `llamascope.py` script
still works on Intel, without the GPU chart.

If you want to see what the system actually knows about this file:

```sh
spctl --assess --type execute --verbose=2 /Applications/LlamaScope.app
```

The answer has to contain `Notarized Developer ID`. A bare `accepted`
is not enough — a locally built bundle is `accepted` **before**
anything is notarized, because it carries no quarantine flag.

---

## How you know it is running

LlamaScope has **no Dock icon** — it is a menu-bar tool and it is meant
to be one (`LSUIElement`). After launching it, look for the icon at the
**top right of the screen**, next to the clock and Wi-Fi.

This is the most common misunderstanding on a first run: an app that
shows nothing in the Dock looks exactly like an app that failed to
start. If the icon is in the bar at the top, everything worked.

## Language

The panel speaks Polish if you have Polish among your system languages
(*System Settings → General → Language & Region*). Otherwise it speaks
English. There is no switch inside the app — a menu-bar tool should
have one setting fewer.

The app's log stays in Polish regardless of that choice. It is material
for a bug report, and it is read by whoever writes this application.

## The proxy, the second program in the bundle

The bundle carries a **second executable**:
`Contents/MacOS/LlamaScopeProxy`. It is a separate process precisely so
that "proxy off" means that process does not exist — checkably, in
Activity Monitor, and not on our word.

It is signed with the same identity and covered by the same
notarization as the app. You do not have to do anything with it
separately.

## What this version does not have

- **Automatic updates.** A new version means a new build or a new file.
- **A Homebrew cask.** That arrives in 1.0.

## How to uninstall it

Move `LlamaScope.app` to the Trash. Two places where the program wrote
something of its own will remain — you can delete both by hand:

```sh
rm -rf ~/Library/Logs/LlamaScope                 # app log, proxy log and observations
rm -rf ~/Library/Application\ Support/LlamaScope # swap-usage baseline
```

That is everything. LlamaScope installs no background services, adds
nothing to your login items and leaves nothing outside those two
directories.

---

## W skrócie (po polsku)

Ten sam dokument po polsku, w całości: [INSTALACJA.md](INSTALACJA.md).
