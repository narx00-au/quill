# ============================================================
#  Quill Office - the back office for OTHER guilds, on one PC
#
#  Runs both halves together on the officer's PC (no server needed):
#    - the bridge: notebook from WoW  ->  Discord review queue
#    - the Discord side: #quill-review cards, AI drafts, approvals
#  Notes and approvals just move between folders on this PC.
#
#  Everything lives in %APPDATA%\QuillOffice (settings.json, token.txt,
#  anthropic_key.txt if the guild uses AI, logs). The setup wizard fills it in.
#  The guild's own keys only - nobody else's.
# ============================================================

import os
import sys
import threading
from pathlib import Path

HOME = Path(os.environ.get("QUILL_HOME") or Path(os.environ.get("APPDATA", Path.home())) / "QuillOffice")
HOME.mkdir(parents=True, exist_ok=True)
os.environ["QUILL_HOME"] = str(HOME)

# Running hidden (no window): send everything printed to a log file instead.
if sys.stdout is None or not sys.stdout.isatty():
    log = open(HOME / "office.log", "a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stderr = log

sys.path.insert(0, str(Path(__file__).resolve().parent))
import quill_bridge      # noqa: E402  (reads QUILL_HOME when it loads)
import quill_bot         # noqa: E402


def run_bridge():
    try:
        quill_bridge.main()
    except Exception as problem:                 # never take the Discord side down with it
        quill_bridge.say(f"Bridge stopped: {problem}")


def main():
    if not (HOME / "token.txt").exists():
        print("Quill Office isn't set up yet - run the Quill setup wizard first.")
        return
    threading.Thread(target=run_bridge, daemon=True).start()
    quill_bot.main()


if __name__ == "__main__":
    main()
