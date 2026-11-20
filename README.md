# Perch

A macOS menu-bar app for [Claude Code](https://claude.com/claude-code). It shows your running agents, their context usage and your plan limits, and lets you answer permission prompts without switching to the terminal.

## Install (fresh Mac)

```bash
git clone https://github.com/DarrenChan99/Agent-Stack.git ~/Agent-Stack
cd ~/Agent-Stack && ./Scripts/setup.sh
```

That's it. The script:

1. Checks you're on macOS 15+ and have the Swift toolchain. If the Command Line Tools are missing it opens their installer; finish it, then run `./Scripts/setup.sh` again.
2. Builds and signs `~/Applications/Perch.app`, then launches it. The first build takes a few minutes.
3. Adds Perch's hooks to `~/.claude/settings.json`. Your other settings are kept, and the old file is backed up to `settings.json.perch-bak`.
4. Installs git hooks so every `git commit` / `git pull` in this repo rebuilds and relaunches the app in the background (log: `~/Library/Logs/Perch-build.log`).

Then:

- **Restart any open Claude Code sessions** so they pick up the hooks.
- Optional: open Perch from the menu bar → **Settings** → **Launch at login**.

Requirements: macOS 15+, Xcode Command Line Tools (`xcode-select --install`), and Claude Code installed and logged in. Perch reads your Claude login for the usage meters; no other setup or API key is needed.

You can run `setup.sh` again at any time; nothing is duplicated.

## Use

| | |
|---|---|
| Click the menu-bar icon | Show agents, context and usage |
| **⌥⌘Space** | Open the panel and jump to waiting prompts |
| Prompt appears | Answer it in the panel, or hand it back to the terminal |

If the app isn't running, the hooks let Claude Code carry on as normal.

## Develop

```bash
swift build                    # debug build
swift test                     # tests (needs full Xcode for the Testing module)
./Scripts/build-app.sh         # rebuild + relaunch ~/Applications/Perch.app by hand
```

Sources: `Sources/Perch` (app), `Sources/perch-hook` (hook binary that Claude Code runs), `Sources/Shared` (socket protocol).

## Troubleshooting

- **Nothing shows up:** restart your Claude Code sessions, then check that `~/.claude/settings.json` contains `perch-hook`. Re-running `./Scripts/setup.sh` fixes this.
- **Auto-rebuild stopped working:** check `~/Library/Logs/Perch-build.log`. If a build was killed partway, run `rm -rf ~/Applications/.perch-build.lock`.
- **Usage bars show "—":** the usage API is rate-limited, and Perch backs off and retries on its own. Make sure you're logged in with `claude`.

## Uninstall

```bash
~/Applications/Perch.app/Contents/MacOS/Perch --uninstall-hooks   # removes only Perch's hooks
osascript -e 'quit app "Perch"'; rm -rf ~/Applications/Perch.app
rm -f .git/hooks/post-commit .git/hooks/post-merge
```

## License notes

Includes code ported from CodexBar (MIT). See [NOTICE](NOTICE).
