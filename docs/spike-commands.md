# Perch spike – commands

## 1. Terminal A: start the server (leave it running)

```bash
cd /Users/darren/Agent-Stack
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build && .build/debug/spike-server
```

## 2. Terminal B: back up settings and add the perch hooks (adds to existing hooks, doesn't replace them)

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.pre-perch
python3 - <<'EOF'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p))
h = d.setdefault("hooks", {})
cmd = {"type": "command", "command": "/Users/darren/Agent-Stack/.build/debug/perch-hook", "timeout": 600}
add = {
    "PermissionRequest": {"matcher": "*", "hooks": [cmd]},
    "PreToolUse": {"matcher": "AskUserQuestion", "hooks": [cmd]},
    "Stop": {"hooks": [cmd]},
    "SessionStart": {"hooks": [cmd]},
}
for event, entry in add.items():
    h.setdefault(event, []).append(entry)
json.dump(d, open(p, "w"), indent=2)
print("perch hooks added")
EOF
```

## 3. Terminal B: start a test session

```bash
claude
```

Inside it, try these and answer in Terminal A:

- `run ls /tmp` → `a` allow / `d` deny; then again with `A` (always allow)
- `ask me a multiple choice question using AskUserQuestion` → type an option number or free text
- let it finish a reply → Stop event; type a reply to continue, or Enter to let it stop

Then Ctrl-C spike-server while a prompt is waiting (check #5), and run once with it stopped (check #4).
Repeat everything in the VS Code Claude panel.

> Note: you already have a `PermissionRequest` hook. If it answers permissions itself, check #1 may never
> reach spike-server. If so, remove that entry temporarily.

## 3b. Permission tests (#1, #7) need default permission mode (auto mode skips the prompt, so no hook fires)

```bash
claude --permission-mode default
```

Then ask: `run touch /tmp/perch-test`. Answer `d`, then retry and `a`, then retry with `A`.

## 4. When done: restore original settings

```bash
cp ~/.claude/settings.json.pre-perch ~/.claude/settings.json
```

Record results in the table in `docs/spike.md`.
