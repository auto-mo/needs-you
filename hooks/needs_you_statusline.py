#!/usr/bin/env python3
"""Claude Code status line command that saves plan limits for the Needs You menu bar app.

Claude Code passes `rate_limits` (current session and weekly usage) to the status line on
every refresh. This script writes that object to <NEEDS_YOU_DIR>/limits.json and then prints
a status line.

If you already had a status line command, the installer passes it as the first argument.
This script runs it with the same stdin and prints its output unchanged, so your status line
looks exactly as before. Without one, it prints a short default line.
"""

import json
import os
import subprocess
import sys
import time


def base_dir():
    return os.environ.get("NEEDS_YOU_DIR") or os.path.expanduser("~/.claude/needs-you")


def save_limits(data):
    limits = data.get("rate_limits")
    if not isinstance(limits, dict) or not limits:
        return
    root = base_dir()
    os.makedirs(root, exist_ok=True)
    path = os.path.join(root, "limits.json")
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w") as f:
        json.dump({"version": 1, "captured_at": time.time(), "rate_limits": limits}, f)
    os.replace(tmp, path)


def default_line(data):
    model = (data.get("model") or {}).get("display_name") or ""
    folder = os.path.basename((data.get("workspace") or {}).get("current_dir") or data.get("cwd") or "")
    return "  ".join(p for p in (model, folder) if p)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = {}
    try:
        save_limits(data)
    except Exception:
        pass

    if len(sys.argv) > 1 and sys.argv[1].strip():
        try:
            out = subprocess.run(sys.argv[1], shell=True, input=raw, capture_output=True,
                                 text=True, timeout=10)
            sys.stdout.write(out.stdout)
            return
        except Exception:
            pass
    print(default_line(data))


if __name__ == "__main__":
    main()
