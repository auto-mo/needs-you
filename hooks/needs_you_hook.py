#!/usr/bin/env python3
"""Claude Code hook for the Needs You menu bar app.

One script handles every event it is registered for, reading the event from stdin:

  PermissionRequest  hand the prompt to the menu bar app and wait for Allow or Deny
  UserPromptSubmit   log "prompt"
  Stop               log "stop"
  Notification       log "idle" when notification_type is idle_prompt
  SessionEnd         log "end"

Run with --await-reply as an async Stop hook with asyncRewake: after a session finishes, it
waits in the background for a reply typed in the menu bar and wakes the session with it
(exit code 2, reply on stderr). It steps aside as soon as you type in the session itself.

File formats are in docs/PROTOCOL.md. Standard library only.

Safety rule: this script must never be the reason a session hangs or errors. Every path
exits 0. If anything goes wrong, or the app is not running, it prints nothing, and Claude Code
carries on exactly as if the hook were not installed.
"""

import json
import os
import signal
import sys
import time

VERSION = 1
HEARTBEAT_MAX_AGE = 10.0  # seconds; older means the app is not running
POLL_INTERVAL = 0.25
EVENTS_TRIM_AT = 4000
EVENTS_KEEP = 2000


def base_dir():
    return os.environ.get("NEEDS_YOU_DIR") or os.path.expanduser("~/.claude/needs-you")


def wait_seconds():
    try:
        return max(5.0, float(os.environ.get("NEEDS_YOU_WAIT_SECONDS", "300")))
    except ValueError:
        return 300.0


def write_json_atomic(path, obj):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def remove_quietly(path):
    try:
        os.remove(path)
    except OSError:
        pass


def app_is_running(root):
    try:
        return time.time() - os.path.getmtime(os.path.join(root, "app.heartbeat")) < HEARTBEAT_MAX_AGE
    except OSError:
        return False


MESSAGE_MAX = 4000  # characters of the last reply kept for the menu's preview


def log_event(root, name, data, message=None):
    os.makedirs(root, exist_ok=True)
    path = os.path.join(root, "events.jsonl")
    line = json.dumps({
        "version": VERSION,
        "ts": time.time(),
        "event": name,
        "session_id": data.get("session_id"),
        "cwd": data.get("cwd"),
        "transcript_path": data.get("transcript_path"),
        "message": message[:MESSAGE_MAX] if isinstance(message, str) and message else None,
    })
    with open(path, "a") as f:
        f.write(line + "\n")
    try:
        if os.path.getsize(path) > EVENTS_TRIM_AT * 300:
            with open(path) as f:
                lines = f.readlines()
            if len(lines) > EVENTS_TRIM_AT:
                tmp = path + ".%d.tmp" % os.getpid()
                with open(tmp, "w") as f:
                    f.writelines(lines[-EVENTS_KEEP:])
                os.replace(tmp, path)
    except OSError:
        pass


REPLY_MAX_WAIT = 24 * 3600 - 60  # just under the 86400 s timeout the installer sets
# Hook feedback isn't shown as a chat message, so Claude is asked to quote the reply first.
REPLY_FRAME = ("The user replied from the Needs You menu bar. Treat this as their next message. "
               "Begin your answer with their message quoted on one line, as "
               "'> **You (from the menu bar):** <their message>', then a blank line, then answer:\n\n")


def clear_waiter(root, session_id):
    if session_id:
        remove_quietly(os.path.join(root, "waiting", session_id + ".json"))


def await_reply(root, data):
    """Returns the reply text, or None if the session moved on without one."""
    sid = data.get("session_id")
    if not sid or "/" in sid:
        return None
    waiting = os.path.join(root, "waiting", sid + ".json")
    reply_path = os.path.join(root, "replies", sid + ".json")
    os.makedirs(os.path.dirname(waiting), exist_ok=True)
    os.makedirs(os.path.dirname(reply_path), exist_ok=True)
    remove_quietly(reply_path)  # a reply meant for an earlier turn is stale
    me = os.getpid()

    def stopped(*_):  # the session was closed: leave no waiting file behind
        remove_quietly(waiting)
        os._exit(0)
    for s in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(s, stopped)
    write_json_atomic(waiting, {"version": VERSION, "session_id": sid, "pid": me, "since": time.time(),
                                "cwd": data.get("cwd"), "transcript_path": data.get("transcript_path")})
    deadline = time.time() + REPLY_MAX_WAIT
    while time.time() < deadline:
        time.sleep(1)
        try:
            with open(waiting) as f:
                if json.load(f).get("pid") != me:
                    return None  # a newer turn took over
        except (OSError, ValueError):
            return None  # removed: you typed in the session, or it ended
        if os.getppid() == 1:
            break  # Claude Code exited
        if os.path.exists(reply_path):
            try:
                with open(reply_path) as f:
                    text = json.load(f).get("text")
            except (OSError, ValueError):
                continue
            remove_quietly(reply_path)
            remove_quietly(waiting)
            return text if isinstance(text, str) and text.strip() else None
    remove_quietly(waiting)
    return None


def handle_permission(root, data):
    if not app_is_running(root):
        return None
    pending_dir = os.path.join(root, "pending")
    answers_dir = os.path.join(root, "answers")
    os.makedirs(pending_dir, exist_ok=True)
    os.makedirs(answers_dir, exist_ok=True)

    rid = "%d-%d" % (int(time.time() * 1000), os.getpid())
    pending_path = os.path.join(pending_dir, rid + ".json")
    answer_path = os.path.join(answers_dir, rid + ".json")
    write_json_atomic(pending_path, {
        "version": VERSION,
        "id": rid,
        "kind": "permission",
        "created_at": time.time(),
        "hook_pid": os.getpid(),
        "session_id": data.get("session_id"),
        "cwd": data.get("cwd"),
        "transcript_path": data.get("transcript_path"),
        "tool_name": data.get("tool_name"),
        "tool_input": data.get("tool_input"),
        "permission_mode": data.get("permission_mode"),
    })

    try:
        deadline = time.time() + wait_seconds()
        while time.time() < deadline:
            if os.path.exists(answer_path):
                try:
                    with open(answer_path) as f:
                        answer = json.load(f)
                except (OSError, ValueError):
                    time.sleep(POLL_INTERVAL)  # half-written; try again
                    continue
                decision = answer.get("decision")
                if decision == "allow":
                    result = {"behavior": "allow"}
                    # Answers to a question (AskUserQuestion) come back as the tool's full input
                    # with an "answers" map; Claude Code uses it instead of showing its own picker.
                    if isinstance(answer.get("updated_input"), dict):
                        result["updatedInput"] = answer["updated_input"]
                    return result
                if decision == "deny":
                    return {"behavior": "deny",
                            "message": answer.get("message") or "Denied from the Needs You menu bar."}
                return None
            if not app_is_running(root):
                return None  # app quit while we waited; hand back to the normal prompt
            time.sleep(POLL_INTERVAL)
        return None
    finally:
        remove_quietly(pending_path)
        remove_quietly(answer_path)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    root = base_dir()
    event = data.get("hook_event_name")

    if "--await-reply" in sys.argv:
        if event == "Stop":
            text = await_reply(root, data)
            if text:
                sys.stderr.write(REPLY_FRAME + text.strip() + "\n")
                sys.exit(2)  # wakes the session (asyncRewake)
        return

    if event == "PermissionRequest":
        decision = handle_permission(root, data)
        if decision:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": decision,
            }}))
    elif event == "UserPromptSubmit":
        clear_waiter(root, data.get("session_id"))
        log_event(root, "prompt", data)
    elif event == "Stop":
        log_event(root, "stop", data, data.get("last_assistant_message"))
    elif event == "Notification" and data.get("notification_type") == "idle_prompt":
        log_event(root, "idle", data, data.get("message"))
    elif event == "SessionEnd":
        clear_waiter(root, data.get("session_id"))
        log_event(root, "end", data)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:  # never break the session
        pass
    sys.exit(0)
