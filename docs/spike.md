# Phase 0 spike (gate)

Nothing in Phase 2+ starts until this passes. Record results in the table at the bottom.

## Run it

1. Build (use Xcode's toolchain; the Command Line Tools lack the Testing module):
   ```
   cd /Users/darren/Agent-Stack
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   swift build
   ```
2. Start the throwaway server in its own terminal and leave it open. It prints every hook event and
   asks for replies on stdin:
   ```
   .build/debug/spike-server
   ```
3. Add the hook by hand to `~/.claude/settings.json` (merge into your existing `hooks` object; back the file up first):
   ```json
   {
     "hooks": {
       "PermissionRequest": [
         { "matcher": "*", "hooks": [{ "type": "command", "command": "/Users/darren/Agent-Stack/.build/debug/perch-hook", "timeout": 600 }] }
       ],
       "PreToolUse": [
         { "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "/Users/darren/Agent-Stack/.build/debug/perch-hook", "timeout": 600 }] }
       ],
       "Stop": [
         { "hooks": [{ "type": "command", "command": "/Users/darren/Agent-Stack/.build/debug/perch-hook", "timeout": 600 }] }
       ],
       "SessionStart": [
         { "hooks": [{ "type": "command", "command": "/Users/darren/Agent-Stack/.build/debug/perch-hook", "timeout": 600 }] }
       ]
     }
   }
   ```
   `perch-hook` self-times-out at (timeout - 10s); override with env `PERCH_HOOK_TIMEOUT` (seconds, default 600).
   The Stop reply is a plain `reply` typed into spike-server; empty input lets Claude stop normally.
4. Remove the entries from settings.json when done.

Server prompts: PermissionRequest `a` allow, `d` deny, `A` allow plus the event's `permission_suggestions` as `updatedPermissions`,
`m` deny with message, Enter = no reply (hook closes, normal prompt). AskUserQuestion: type an option number or free text per
question (empty = no reply). Stop: type a reply, or Enter to let it stop.

Run the checklist once in Terminal (`claude`) and once in VS Code's native Claude panel.

## Checklist

| # | Check | Terminal | VS Code |
|---|-------|----------|---------|
| 1 | PermissionRequest allow + deny work (trigger a Bash command) | ASSUMED | ASSUMED |
| 2 | AskUserQuestion answers work: single question, multiple questions, free text | free text PASS; rest ASSUMED | ASSUMED |
| 3 | Stop reply (`decision: block`) continues the session | PASS | ASSUMED |
| 4 | Server down (spike-server not running): normal prompt appears instantly | ASSUMED | ASSUMED |
| 5 | Server killed (Ctrl-C) mid-wait: normal prompt appears | ASSUMED | ASSUMED |
| 6 | While the hook is blocking, can the terminal/IDE prompt still be answered? (decides the "jump to terminal" UX) | ASSUMED | ASSUMED |
| 7 | `updatedPermissions` from `permission_suggestions` works for "Always allow" (use `A`) | ASSUMED | ASSUMED |
| 8 | What happens when the hook timeout fires? (set `"timeout": 30` and wait) | ASSUMED | ASSUMED |

Also note: does VS Code fire these hooks at all? If not, prompts are Terminal-only for MVP and VS Code sessions only appear in the list.

**Gate: passed on assumption (2026-11-19, owner call).** ASSUMED = untested; revisit if Phase 2+ hits problems.

Notes / field-name corrections found:

- 2026-11-19 Terminal: hook fires for SessionStart/Stop/PreToolUse; `app=?` and `tty=-` on every event (app/tty detection not working).
- Stop fires after every reply in every session and blocks until answered; real app must not block Stop by default.
- PermissionRequest does NOT fire in auto mode (no prompt shown, so no hook). Test #1/#7 in default permission mode.
