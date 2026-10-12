#!/usr/bin/env python3
"""Install or remove the Needs You hooks in Claude Code's user settings.

  python3 scripts/install.py              install (or update) hooks and the status line
  python3 scripts/install.py --dry-run    show what would change, write nothing
  python3 scripts/install.py --uninstall  remove everything this script added
  python3 scripts/install.py --no-statusline       skip the plan-limits status line
  python3 scripts/install.py --use-claude-icon     use the menu bar icon from your own Claude app
  python3 scripts/install.py --launch-at-login     start ~/Applications/Needs You.app when you log in

The scripts are copied to ~/.claude/needs-you/bin/, so the repo can be moved or deleted
afterwards. ~/.claude/settings.json is backed up before every change. Hooks you already have
are left alone; this script only adds or removes entries whose command points at its own files.
"""

import argparse
import json
import os
import shutil
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLAUDE_DIR = os.path.expanduser("~/.claude")
SETTINGS = os.path.join(CLAUDE_DIR, "settings.json")
DATA_DIR = os.environ.get("NEEDS_YOU_DIR") or os.path.join(CLAUDE_DIR, "needs-you")
BIN_DIR = os.path.join(DATA_DIR, "bin")
STATE = os.path.join(DATA_DIR, "install-state.json")
ICON_DIR = os.path.expanduser("~/.config/needs-you")
CLAUDE_APP_ICON = "/Applications/Claude.app/Contents/Resources/TrayIconTemplate{}.png"

APP = os.path.expanduser("~/Applications/Needs You.app")
AGENT_LABEL = "dev.needsyou.menubar"
AGENT = os.path.expanduser("~/Library/LaunchAgents/%s.plist" % AGENT_LABEL)

HOOK = os.path.join(BIN_DIR, "needs_you_hook.py")
STATUSLINE = os.path.join(BIN_DIR, "needs_you_statusline.py")
MARKER = "needs_you_"  # every command we add contains this

# event -> (matcher, timeout seconds, async)
EVENTS = {
    "PermissionRequest": ("", 330, False),  # waits for the menu; hook gives up at 300 s
    "UserPromptSubmit": ("", 5, True),
    "Stop": ("", 5, True),
    "Notification": ("idle_prompt", 5, True),
    "SessionEnd": ("", 5, True),
}


def shq(path):
    return "'" + path.replace("'", "'\\''") + "'"


def is_ours(cmd):
    return isinstance(cmd, str) and MARKER in cmd and "needs-you" in cmd


def load_settings():
    if not os.path.exists(SETTINGS):
        return {}
    with open(SETTINGS) as f:
        return json.load(f)


def strip_ours(settings):
    hooks = settings.get("hooks") or {}
    for event in list(hooks):
        groups = []
        for group in hooks[event]:
            kept = [h for h in group.get("hooks", []) if not is_ours(h.get("command"))]
            if kept:
                groups.append(dict(group, hooks=kept))
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    if "hooks" in settings and not hooks:
        del settings["hooks"]


def add_ours(settings):
    hooks = settings.setdefault("hooks", {})
    for event, (matcher, timeout, is_async) in EVENTS.items():
        entry = {"type": "command", "command": "python3 " + shq(HOOK), "timeout": timeout}
        if is_async:
            entry["async"] = True
        hooks.setdefault(event, []).append({"matcher": matcher, "hooks": [entry]})
    # Waits in the background after each turn for a reply typed in the menu bar.
    hooks["Stop"].append({"matcher": "", "hooks": [{
        "type": "command", "command": "python3 " + shq(HOOK) + " --await-reply",
        "async": True, "asyncRewake": True,
        # Claude Code stops async hooks at the default 600 s; a reply can come hours later.
        "timeout": 86400}]})


def install_statusline(settings, state):
    current = settings.get("statusLine")
    if current and is_ours(current.get("command")):
        return  # already installed; keep the original we saved last time
    previous = current.get("command") if current and current.get("type") == "command" else None
    state["previous_statusline"] = current
    cmd = "python3 " + shq(STATUSLINE)
    if previous:
        cmd += " " + shq(previous)
    settings["statusLine"] = dict(current or {}, type="command", command=cmd)


def restore_statusline(settings, state):
    current = settings.get("statusLine")
    if not (current and is_ours(current.get("command"))):
        return
    previous = state.get("previous_statusline")
    if previous:
        settings["statusLine"] = previous
    else:
        del settings["statusLine"]


def copy_scripts():
    os.makedirs(BIN_DIR, exist_ok=True)
    for name in ("needs_you_hook.py", "needs_you_statusline.py"):
        dst = os.path.join(BIN_DIR, name)
        shutil.copyfile(os.path.join(REPO, "hooks", name), dst)
        os.chmod(dst, 0o755)


def copy_claude_icon():
    src1, src2 = CLAUDE_APP_ICON.format(""), CLAUDE_APP_ICON.format("@2x")
    if not os.path.exists(src1):
        print("Claude app icon not found at %s; keeping the default icon." % src1)
        return
    os.makedirs(ICON_DIR, exist_ok=True)
    shutil.copyfile(src1, os.path.join(ICON_DIR, "icon.png"))
    if os.path.exists(src2):
        shutil.copyfile(src2, os.path.join(ICON_DIR, "icon@2x.png"))
    print("Using the menu bar icon from your Claude app (copied to %s)." % ICON_DIR)


def install_login_item():
    if not os.path.isdir(APP):
        print("Copy the app to %s first (see README), then run this again." % APP)
        return
    import plistlib
    os.makedirs(os.path.dirname(AGENT), exist_ok=True)
    with open(AGENT, "wb") as f:
        plistlib.dump({
            "Label": AGENT_LABEL,
            "ProgramArguments": ["/usr/bin/open", "-a", APP],
            "RunAtLoad": True,
            "LimitLoadToSessionType": "Aqua",
        }, f)
    print("Needs You will start when you log in (%s)." % AGENT)


def remove_login_item():
    if os.path.exists(AGENT):
        os.system("launchctl bootout gui/%d %s 2>/dev/null" % (os.getuid(), shq(AGENT)))
        os.remove(AGENT)
        print("Removed the login item.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-statusline", action="store_true")
    ap.add_argument("--use-claude-icon", action="store_true")
    ap.add_argument("--launch-at-login", action="store_true")
    args = ap.parse_args()

    before = load_settings()
    settings = json.loads(json.dumps(before))
    state = {}
    if os.path.exists(STATE):
        with open(STATE) as f:
            state = json.load(f)

    strip_ours(settings)
    if args.uninstall:
        restore_statusline(settings, state)
    else:
        add_ours(settings)
        if not args.no_statusline:
            install_statusline(settings, state)

    if args.dry_run:
        print(json.dumps({k: settings.get(k) for k in ("hooks", "statusLine")}, indent=2))
        print("\nDry run: nothing written.")
        return

    if settings != before:
        if os.path.exists(SETTINGS):
            stamp = time.strftime("%Y%m%d-%H%M%S")
            backup, n = "%s.bak-needs-you-%s" % (SETTINGS, stamp), 1
            while os.path.exists(backup):
                n += 1
                backup = "%s.bak-needs-you-%s-%d" % (SETTINGS, stamp, n)
            shutil.copyfile(SETTINGS, backup)
            print("Backed up settings to " + backup)
        os.makedirs(CLAUDE_DIR, exist_ok=True)
        tmp = SETTINGS + ".needs-you.tmp"
        with open(tmp, "w") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
        os.replace(tmp, SETTINGS)

    if args.uninstall:
        remove_login_item()
        for path in (HOOK, STATUSLINE, STATE):
            if os.path.exists(path):
                os.remove(path)
        print("Removed the Needs You hooks. Your other hooks and settings are unchanged.")
        return

    copy_scripts()
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(state, f, indent=2)
    if args.use_claude_icon:
        copy_claude_icon()
    if args.launch_at_login:
        install_login_item()
    print("Installed. Hooks apply to Claude Code sessions started from now on.")


if __name__ == "__main__":
    sys.exit(main())
