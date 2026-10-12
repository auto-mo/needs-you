# Protocol

The hook (`hooks/needs_you_hook.py`) and the menu bar app talk only through files in one
folder. There is no server and no network.

**Folder:** `~/.claude/needs-you/` (override with the `NEEDS_YOU_DIR` environment variable,
which both sides honour). All writes are atomic: write `name.tmp`, then rename.

| Path | Written by | Read by | Purpose |
|---|---|---|---|
| `app.heartbeat` | app, every 2 s while running | hook | The hook waits for an answer only if this file's mtime is under 10 s old. If the app is not running, the hook exits at once and Claude Code shows its normal prompt. |
| `pending/<id>.json` | hook | app | One permission prompt that is waiting. |
| `answers/<id>.json` | app | hook | The answer to one prompt. |
| `events.jsonl` | hook | app | One JSON object per line: session lifecycle events. |
| `limits.json` | status line script | app | Last plan-limit snapshot. |
| `waiting/<session_id>.json` | hook | app | A finished session that can take a reply from the menu bar. |
| `replies/<session_id>.json` | app | hook | Your reply to that session. |

## pending/<id>.json

```json
{
  "version": 1,
  "id": "1791676000123-48211",
  "kind": "permission",
  "created_at": 1791676000.123,
  "hook_pid": 48211,
  "session_id": "019ff605-...",
  "cwd": "/Users/me/project",
  "transcript_path": "/Users/me/.claude/projects/.../019ff605-....jsonl",
  "tool_name": "Bash",
  "tool_input": {"command": "npm test", "description": "Run tests"},
  "permission_mode": "default"
}
```

`id` is `<epoch ms>-<hook pid>`. The app treats a pending file as stale, and deletes it, when
`hook_pid` is no longer alive. That happens if the session was answered in its own window or
was closed.

## answers/<id>.json

```json
{"version": 1, "id": "...", "decision": "allow", "answered_at": 1791676010.5}
```

`decision` is `"allow"` or `"deny"`. An allow may carry `"updated_input"`, which the hook
passes on as `updatedInput`. The app uses this to answer a question (`tool_name`
`AskUserQuestion`): it sends back the original `questions` plus
`"answers": {"<question text>": "<chosen label>"}`. For a multi-select question, the labels are
joined with ", ". A deny may carry `"message"`, which the hook passes to
Claude as the reason. On reading an answer, the hook deletes both files and prints the
documented `PermissionRequest` decision JSON. If the answer is missing when the hook times out
(default 300 s, set with `NEEDS_YOU_WAIT_SECONDS`), the hook deletes the pending file and exits
with no output, so the normal prompt takes over.

## events.jsonl

```json
{"version": 1, "ts": 1791676000.1, "event": "stop", "session_id": "...", "cwd": "...", "transcript_path": "...", "message": "Done. Should I also update the tests?"}
```

`message` is optional: for `stop`, the session's last reply (`last_assistant_message`, cut to
4000 characters), shown as a preview in the menu. For `idle`, Claude Code's notification text.

`event` is one of `prompt` (UserPromptSubmit), `stop` (Stop), `idle` (Notification with
`notification_type` `idle_prompt`) or `end` (SessionEnd). The app reads the whole file. The hook
trims it to the last 2000 lines when it grows past 4000.

## Replies

After each turn, a second Stop hook (`--await-reply`, registered with `async` and
`asyncRewake`) writes `waiting/<session_id>.json` (`{"pid", "since", "cwd", ...}`) and waits in
the background. When the app writes `replies/<session_id>.json`
(`{"version": 1, "session_id": "...", "text": "...", "sent_at": ...}`), the hook deletes both
files, prints the reply on stderr and exits with code 2. Claude Code then wakes the session,
which receives the reply as Stop hook feedback. The waiting file is removed, and the hook exits
quietly, when you type in the session itself (UserPromptSubmit), when the session ends, or when
a newer turn starts waiting. The installer sets `timeout: 86400` on this hook, because Claude Code otherwise stops
async hooks at the default 600 s. The app shows Reply only while the waiter's `pid` is alive.

## limits.json

```json
{"version": 1, "captured_at": 1791676000.0, "rate_limits": { "...": "exactly as Claude Code passed it to the status line" }}
```

The app reads `rate_limits` defensively: it shows the windows it recognises and ignores the rest.

## Sessions (read-only, not written by this project)

`~/.claude/sessions/<pid>.json` is Claude Code's own state file, one per running session, with
`sessionId`, `cwd`, `name`, `status` (`busy` / `idle`), `entrypoint` and `updatedAt`. It is
undocumented, so the app treats it as best effort. A session counts as live only while its
`pid` is alive.
