# ============================================================
#  Quill - the bridge  (runs on the PC that plays WoW)
#  Normally runs hidden, started with Windows. Its diary is C:\Quill\bridge.log
#
#  What this does, every 15 seconds:
#    1. Looks at Quill's notebook - the file WoW saves when you
#       /reload or log out (WTF\Account\...\SavedVariables\Quill.lua).
#    2. Picks out anything new since last time.
#    3. Sends it to the server, where Quill posts it in #quill-review.
#  And every 2 minutes:
#    4. Fetches what officers approved (approved.json) from the server,
#       keeps a backup copy in C:\Quill\learned, and writes it into
#       the addon as QuillLearned.lua - in game, /reload to use it.
#
#  Think of it as a log shipper: watch a file, forward new lines.
#  Lines starting with # are notes for humans. Python skips them.
# ============================================================

import glob
import os
import json
import re
import socket
import subprocess
import sys
import time
from pathlib import Path


# ---- Settings ------------------------------------------------

# Where Quill keeps his files: C:\Quill normally; the Quill Office app sets QUILL_HOME to its own folder.
QUILL_FOLDER = Path(os.environ.get("QUILL_HOME") or Path(__file__).resolve().parent.parent)
try:
    SETTINGS = json.loads((QUILL_FOLDER / "settings.json").read_text(encoding="utf-8"))
except (FileNotFoundError, ValueError):
    SETTINGS = {}

# The server the Discord side runs on. None = "local": the Discord side runs on THIS PC (Quill Office),
# so notes and approvals just move between folders - no server, no SSH.
SERVER       = SETTINGS.get("server")          # None = Quill Office on this PC
WOW_FOLDER   = SETTINGS.get("wow_folder", r"C:\Program Files (x86)\World of Warcraft")   # beta now, Forever at launch
CHECK_EVERY  = 15                                    # seconds between looks at the notebook

SENT_FILE    = QUILL_FOLDER / "bridge_sent.json"         # remembers what's already gone up
OUTBOX       = QUILL_FOLDER / "outbox"                   # waiting room if the server can't be reached
LEARNED      = QUILL_FOLDER / "learned"                  # PC copy of everything officers approved
FETCH_EVERY  = 120                                       # seconds between fetching approvals


NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)   # stop scp flashing a black window every 2 minutes
LOG_FILE = QUILL_FOLDER / "bridge.log"   # C:\Quill\bridge.log


def say(text):
    """Write a line to bridge.log (and to the window, if there is one)."""
    line = time.strftime("%Y-%m-%d %H:%M:%S") + "  " + text
    print(line, flush=True)
    try:
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > 1_000_000:     # keep the log under ~1 MB
            LOG_FILE.replace(LOG_FILE.with_suffix(".old.log"))
        with LOG_FILE.open("a", encoding="utf-8") as log:
            log.write(line + "\n")
    except OSError:
        pass


# ---- Reading WoW's save file ---------------------------------
# WoW saves addon data as Lua, e.g.  ["kind"] = "teach",
# This turns that into Python lists and dictionaries.

TOKEN = re.compile(r'''
    \s+ | --[^\n]*                      # spaces and comments: skip
  | (?P<str>"(?:\\.|[^"\\])*")          # "a string"
  | (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<word>[A-Za-z_]\w*)
  | (?P<sym>[\[\]{}=,;])
''', re.VERBOSE | re.DOTALL)


def _unescape(raw):
    def swap(match):
        code = match.group(1)
        if code.isdigit():
            return chr(int(code))
        return {"n": "\n", "t": "\t", "r": "\r"}.get(code, code)
    return re.sub(r'\\(\d{1,3}|.)', swap, raw[1:-1], flags=re.DOTALL)


def _tokens(text):
    for match in TOKEN.finditer(text):
        kind = match.lastgroup
        if kind:
            yield kind, match.group(kind)


def read_lua(text):
    """Turn a WoW SavedVariables file into {name: value}."""
    tokens = list(_tokens(text))
    pos = 0

    def value():
        nonlocal pos
        kind, tok = tokens[pos]
        pos += 1
        if kind == "str":
            return _unescape(tok)
        if kind == "num":
            return float(tok) if any(c in tok for c in ".eE") else int(tok)
        if kind == "word":
            return {"true": True, "false": False, "nil": None}.get(tok, tok)
        if tok == "{":
            return table()
        raise ValueError(f"didn't expect {tok!r}")

    def table():
        nonlocal pos
        result, next_index = {}, 1
        while tokens[pos][1] != "}":
            if tokens[pos][1] == "[":                    # ["key"] = value
                pos += 1
                key = value()
                pos += 2                                 # skip ] and =
                result[key] = value()
            elif tokens[pos][0] == "word" and pos + 1 < len(tokens) and tokens[pos + 1][1] == "=":
                key = tokens[pos][1]                     # key = value
                pos += 2
                result[key] = value()
            else:                                        # plain list item
                result[next_index] = value()
                next_index += 1
            if tokens[pos][1] in (",", ";"):
                pos += 1
        pos += 1
        if result and all(isinstance(k, int) for k in result) and sorted(result) == list(range(1, len(result) + 1)):
            return [result[i] for i in range(1, len(result) + 1)]
        return result

    found = {}
    while pos < len(tokens):
        name = tokens[pos][1]
        pos += 2                                         # skip the =
        found[name] = value()
    return found


# ---- Bringing approvals back into the game -------------------

def lua_text(value):
    """Make text safe to put inside a Lua file, and safe for WoW chat."""
    text = str(value or "").replace("|", "/")             # | starts colour codes in WoW chat
    text = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + text.replace("\r", "").replace("\n", " ") + '"'


def learned_version(data):
    """The time of the newest approval - so the number only ever goes up."""
    times = [item.get("when", 0) for key in ("answers", "facts", "jokes") for item in data.get(key, [])]
    return max(times + [data.get("changed", 0), 1])      # "changed" moves on when officers cancel an announcement


def write_learned(data):
    lua = make_learned_lua(data)
    for folder in addon_folders():
        (folder / "QuillLearned.lua").write_text(lua, encoding="utf-8")


def make_learned_lua(data):
    lines = ["-- Written by the Quill bridge from what officers approved in Discord.",
             "-- Don't edit by hand - it gets replaced every couple of minutes.",
             "QuillLearned = {",
             f"    bridgePC = {lua_text(os.environ.get('COMPUTERNAME', 'this PC'))},   -- tells the addon it's on the bridge PC",
             f"    version = {learned_version(data)},   -- goes up with every approval; copies swap to the newest",
             "    answers = {"]
    for item in data.get("answers", []):
        lines.append(f"        {{ q = {lua_text(item.get('question'))}, a = {lua_text(item.get('answer'))}, "
                     f"asker = {lua_text(item.get('asker'))}, by = {lua_text(item.get('by'))}, "
                     f"patch = {lua_text(item.get('patch', ''))}, when = {int(item.get('when', 0))} }},")
    lines.append("    },")
    lines.append("    facts = {")
    for item in data.get("facts", []):
        lines.append(f"        {{ text = {lua_text(item.get('text'))}, author = {lua_text(item.get('author'))}, "
                     f"by = {lua_text(item.get('by'))} }},")
    lines.append("    },")
    lines.append("    jokes = {")
    for item in data.get("jokes", []):
        lines.append(f"        {{ text = {lua_text(item.get('text'))}, author = {lua_text(item.get('author'))} }},")
    lines.append("    },")
    lines.append("    announcements = {")
    for item in data.get("announcements", []):
        lines.append(f"        {{ id = {lua_text(item.get('id'))}, day = {lua_text(item.get('day'))}, "
                     f"time = {lua_text(item.get('time'))}, text = {lua_text(item.get('text'))}, "
                     f"repeating = {'true' if item.get('repeating') else 'false'} }},")
    lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def addon_folders():
    pattern = WOW_FOLDER + r"\_*_\Interface\AddOns\Quill"
    return [Path(p) for p in glob.glob(pattern)]


def fetch_approved(last):
    """Fetch approved.json from the server. Returns its text (or the old text if nothing new)."""
    LEARNED.mkdir(exist_ok=True)
    incoming = LEARNED / "approved_download.json"
    if not SERVER:                                   # local: read the Discord side's file directly
        source = QUILL_FOLDER / "approved.json"
        if not source.exists():
            return last
        incoming.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    result = subprocess.run(
        ["scp", "-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
         f"{SERVER}:quill/approved.json", str(incoming)],
        capture_output=True, text=True, creationflags=NO_WINDOW) if SERVER else None
    if result is not None and result.returncode != 0:
        return last                       # nothing approved yet, or server unreachable - try later
    text = incoming.read_text(encoding="utf-8")
    incoming.unlink()
    if text == last:
        return last
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return last

    (LEARNED / "approved.json").write_text(text, encoding="utf-8")            # the PC backup
    write_learned(data)
    counts = ", ".join(f"{len(data.get(k, []))} {k}" for k in ("answers", "facts", "jokes"))
    say(f"Updated what Quill knows ({counts}). In game, /reload to use it.")
    return text


# ---- Finding and sending -------------------------------------

def notebook_files():
    pattern = WOW_FOLDER + r"\_*_\WTF\Account\*\SavedVariables\Quill.lua"
    return [Path(p) for p in glob.glob(pattern)]


def entry_key(entry):
    return f"{entry.get('when')}|{entry.get('name')}|{entry.get('kind')}|{entry.get('text')}"


def load_sent():
    try:
        return set(json.loads(SENT_FILE.read_text(encoding="utf-8")))
    except (FileNotFoundError, json.JSONDecodeError):
        return set()


def save_sent(sent):
    SENT_FILE.write_text(json.dumps(sorted(sent), indent=1), encoding="utf-8")


def upload_outbox():
    """Send every waiting file to the server. Returns True if the outbox is now empty."""
    if not SERVER:                                   # local: the Discord side is on this PC
        incoming = QUILL_FOLDER / "incoming"
        incoming.mkdir(exist_ok=True)
        for path in sorted(OUTBOX.glob("*.json")):
            path.replace(incoming / path.name)
        return True
    for path in sorted(OUTBOX.glob("*.json")):
        result = subprocess.run(
            ["scp", "-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
             str(path), f"{SERVER}:quill/incoming/"],
            capture_output=True, text=True, creationflags=NO_WINDOW)
        if result.returncode != 0:
            say("Couldn't reach the server - will try again shortly.")
            say("  (If this keeps happening: open PowerShell and run  ssh-add )")
            if result.stderr.strip():
                say("  " + result.stderr.strip().splitlines()[-1])
            return False
        path.unlink()
    return True


def check_once(sent):
    new = []
    for path in notebook_files():
        try:
            data = read_lua(path.read_text(encoding="utf-8", errors="replace"))
        except Exception as problem:
            say(f"Couldn't read {path}: {problem}")
            continue
        for entry in (data.get("QuillDB") or {}).get("inbox") or []:
            if isinstance(entry, dict) and entry_key(entry) not in sent:
                new.append({"kind": entry.get("kind", "note"), "name": entry.get("name", "?"),
                            "text": entry.get("text", ""), "when": entry.get("when"),
                            "patch": entry.get("patch", "")})

    if new:
        OUTBOX.mkdir(exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        (OUTBOX / f"{stamp}.json").write_text(json.dumps(new, ensure_ascii=False, indent=1), encoding="utf-8")
        for entry in new:
            sent.add(entry_key(entry))
        save_sent(sent)
        say(f"Found {len(new)} new note(s) in Quill's notebook.")

    if any(OUTBOX.glob("*.json")) if OUTBOX.exists() else False:
        if upload_outbox():
            say("Sent to the server. Check #quill-review." if SERVER else "Passed to Discord. Check #quill-review.")


def already_running():
    """Only one bridge at a time: the first one claims a private port on this PC."""
    global _lock
    _lock = socket.socket()
    try:
        _lock.bind(("127.0.0.1", 47731))
        return False
    except OSError:
        return True


def main():
    if already_running():
        say("Another bridge is already running - this one is closing.")
        return
    say("Quill bridge running.")
    say("New notes go up after you /reload or log out (that's when WoW saves them).")
    files = notebook_files()
    if files:
        for path in files:
            say(f"Watching {path}")
    else:
        say(f"No Quill notebook found yet under {WOW_FOLDER}.")
        say("Log in with Quill enabled and type /reload - then it'll appear.")

    sent = load_sent()
    try:
        last = (LEARNED / "approved.json").read_text(encoding="utf-8")
        data = json.loads(last)
    except (FileNotFoundError, json.JSONDecodeError):
        last, data = None, {}
    write_learned(data)          # stamps the addon as the bridge PC's copy, even before any approvals
    next_fetch = 0
    while True:
        check_once(sent)
        if time.time() >= next_fetch:
            last = fetch_approved(last)
            next_fetch = time.time() + FETCH_EVERY
        time.sleep(CHECK_EVERY)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
