# ============================================================
#  Quill Setup - the wizard for ONE officer per guild
#
#  Guildies don't need this: they just install the Quill addon.
#  This sets up the optional back office on the officer's PC:
#    - Discord: a private review queue where officers approve what Quill learns
#    - AI: drafts answers to questions Quill can't answer (the guild's own key)
#  Everything is saved in %APPDATA%\QuillOffice and runs on this PC only.
#
#  Quill was designed by narx00 and coded by Claude (claude.ai), Anthropic's AI.
# ============================================================

import glob
import json
import os
import shutil
import subprocess
import sys
import threading
import tkinter as tk
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path
from tkinter import filedialog, ttk

APP_NAME = "Quill Setup"
HOME = Path(os.environ.get("QUILL_HOME") or Path(os.environ.get("APPDATA", Path.home())) / "QuillOffice")
HERE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))   # bundled files (exe) or repo
ADDON_SOURCE = HERE / "addon" / "Quill"
CREDIT = "Quill was designed by narx00 and coded by Claude (claude.ai), Anthropic's AI."
USER_AGENT = "DiscordBot (https://github.com/narx00-au/quill, 1.0)"

# What Quill's bot may do in your Discord: see and post in its channels, add reactions,
# and create its own channels (+ set who can see them) during setup.
PERMISSIONS = (1024 | 2048 | 16384 | 65536 | 64 | 16 | 268435456)
VIEW, SEND, EMBED, HISTORY, REACT = 1024, 2048, 16384, 65536, 64
MESSAGE_CONTENT_FLAGS = (1 << 18) | (1 << 19)


# ---- Talking to Discord and Anthropic (plain web requests) ---

def discord(path, token, method="GET", body=None):
    request = urllib.request.Request(
        "https://discord.com/api/v10" + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bot " + token, "User-Agent": USER_AGENT, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read() or b"null")


def test_ai_key(key):
    """Returns (ok, message)."""
    request = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", method="POST",
        data=json.dumps({"model": "claude-haiku-5-5", "max_tokens": 5,
                         "messages": [{"role": "user", "content": "Say hi"}]}).encode(),
        headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30):
            return True, "Key works."
    except urllib.error.HTTPError as problem:
        detail = problem.read().decode(errors="ignore")
        if problem.code == 401:
            return False, "Anthropic didn't accept that key. Copy it again from API Keys."
        if "credit" in detail.lower():
            return False, "The key is fine, but the account has no credit yet. Add some under Billing, then test again."
        return False, f"Anthropic said: {problem.code} {detail[:150]}"
    except Exception as problem:
        return False, f"Couldn't reach Anthropic: {problem}"


# ---- Finding World of Warcraft -------------------------------

def find_wow_folders():
    """Likely WoW install folders on this PC (the folder that holds _forever_, _retail_ and so on)."""
    found = []
    try:
        import winreg
        for root in (r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                     r"SOFTWARE\Blizzard Entertainment\World of Warcraft"):
            try:
                with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, root) as key:
                    path = Path(winreg.QueryValueEx(key, "InstallPath")[0])
                    found.append(path.parent if path.name.startswith("_") else path)
            except OSError:
                pass
    except ImportError:
        pass
    for drive in "CDEFGH":
        for guess in (r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft",
                      r"World of Warcraft", r"Games\World of Warcraft", r"Battle.net\World of Warcraft"):
            found.append(Path(f"{drive}:\\") / guess)
    seen, result = set(), []
    for folder in found:
        if folder.exists() and str(folder).lower() not in seen and game_versions(folder):
            seen.add(str(folder).lower())
            result.append(folder)
    return result


def game_versions(wow_folder):
    """The game versions inside a WoW folder: _forever_, _classic_beta_, _retail_..."""
    return sorted(p.name for p in Path(wow_folder).glob("_*_") if p.is_dir())


def addon_installed(wow_folder, version):
    return (Path(wow_folder) / version / "Interface" / "AddOns" / "Quill" / "Quill.toc").exists()


def install_addon(wow_folder, version):
    target = Path(wow_folder) / version / "Interface" / "AddOns" / "Quill"
    target.mkdir(parents=True, exist_ok=True)
    for path in ADDON_SOURCE.iterdir():
        if path.suffix in (".lua", ".toc") and not (path.name == "QuillGuild.lua" and (target / path.name).exists()):
            shutil.copy2(path, target / path.name)           # never overwrite the guild's own settings file
    return target


# ---- Starting Quill Office with Windows ----------------------

def office_command():
    """How to start Quill Office: the exe this setup carries inside it, or Python + the script while developing."""
    if getattr(sys, "frozen", False):
        # QuillSetup.exe carries QuillOffice.exe inside it. Copy it somewhere permanent (not Downloads, not the
        # temporary unpack folder) so the Windows startup shortcut keeps working.
        home = Path(os.environ.get("APPDATA", Path.home())) / "QuillOffice"
        home.mkdir(parents=True, exist_ok=True)
        installed, carried = home / "QuillOffice.exe", HERE / "QuillOffice.exe"
        if carried.exists():
            try:
                shutil.copy2(carried, installed)
            except PermissionError:
                pass                             # it's running right now - the copy already there is fine
        return [str(installed)]
    pythonw = Path(sys.executable).with_name("pythonw.exe")
    return [str(pythonw if pythonw.exists() else sys.executable), str(Path(__file__).with_name("quill_office.py"))]


def set_autostart(enabled):
    startup = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
    shortcut = startup / "Quill Office.lnk"
    if not enabled:
        shortcut.unlink(missing_ok=True)
        return
    command = office_command()
    script = ("$s = (New-Object -ComObject WScript.Shell).CreateShortcut('" + str(shortcut) + "'); "
              "$s.TargetPath = '" + command[0] + "'; "
              "$s.Arguments = '" + " ".join(f'"{c}"' for c in command[1:]) + "'; "
              "$s.Description = 'Quill Office - the guild back office'; $s.Save()")
    subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def start_office():
    subprocess.Popen(office_command(), creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                     env=dict(os.environ, QUILL_HOME=str(HOME)))


# ============================================================
#  The windows
# ============================================================

class Wizard(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(APP_NAME)
        self.geometry("760x600")
        self.minsize(700, 560)
        self.configure(bg="#1e1b24")
        self.state = {"wow": None, "version": None, "discord": None, "token": "", "bot_name": "", "bot_id": "",
                      "client_id": "", "server_id": "", "server_name": "", "officer_role": "", "ai": None,
                      "ai_key": "", "autostart": True, "make_channels": True}
        self._style()
        self.pages = [WelcomePage, WowPage, DiscordChoicePage, BotPage, ServerPage, AiPage, FinishPage]
        self.index = 0
        self.body = tk.Frame(self, bg="#1e1b24")
        self.body.pack(fill="both", expand=True, padx=28, pady=(22, 8))
        nav = tk.Frame(self, bg="#1e1b24")
        nav.pack(fill="x", padx=28, pady=(0, 20))
        self.progress = tk.Label(nav, bg="#1e1b24", fg="#9a90a8", font=("Segoe UI", 9))
        self.progress.pack(side="left")
        self.next_button = ttk.Button(nav, text="Next  ›", style="Accent.TButton", command=self.next)
        self.next_button.pack(side="right")
        self.back_button = ttk.Button(nav, text="‹  Back", command=self.back)
        self.back_button.pack(side="right", padx=(0, 10))
        self.show()

    def _style(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TButton", font=("Segoe UI", 10), padding=(14, 7), background="#3a3446",
                        foreground="#f1ecf7", borderwidth=0)
        style.map("TButton", background=[("active", "#4a4358"), ("disabled", "#2a2632")],
                  foreground=[("disabled", "#6f6680")])
        style.configure("Accent.TButton", background="#c8a2c8", foreground="#1e1b24", font=("Segoe UI", 10, "bold"))
        style.map("Accent.TButton", background=[("active", "#d9b9d9"), ("disabled", "#5a4d5a")])
        style.configure("TRadiobutton", background="#1e1b24", foreground="#f1ecf7", font=("Segoe UI", 11))
        style.configure("TCheckbutton", background="#1e1b24", foreground="#f1ecf7", font=("Segoe UI", 10))
        style.configure("TCombobox", padding=5)
        style.configure("TEntry", padding=6)

    def visible_pages(self):
        pages = [WelcomePage, WowPage, DiscordChoicePage]
        if self.state["discord"]:
            pages += [BotPage, ServerPage, AiPage]
        return pages + [FinishPage]

    def show(self):
        for child in self.body.winfo_children():
            child.destroy()
        pages = self.visible_pages()
        self.page = pages[self.index](self.body, self)
        self.page.pack(fill="both", expand=True)
        self.progress.config(text=f"Step {self.index + 1} of {len(pages)}")
        self.back_button.state(["disabled"] if self.index == 0 else ["!disabled"])
        self.next_button.config(text="Finish" if pages[self.index] is FinishPage else "Next  ›")
        self.refresh()

    def refresh(self):
        ok = self.page.ready()
        self.next_button.state(["!disabled"] if ok else ["disabled"])

    def next(self):
        pages = self.visible_pages()
        if pages[self.index] is FinishPage:
            self.page.finish()
            return
        self.page.leave()
        self.index = min(self.index + 1, len(self.visible_pages()) - 1)
        self.show()

    def back(self):
        self.index = max(0, self.index - 1)
        self.show()


class Page(tk.Frame):
    def __init__(self, parent, wizard):
        super().__init__(parent, bg="#1e1b24")
        self.wizard, self.state = wizard, wizard.state
        self.build()

    def build(self):
        pass

    def ready(self):
        return True

    def leave(self):
        pass

    # little helpers for consistent text
    def title(self, text):
        tk.Label(self, text=text, bg="#1e1b24", fg="#c8a2c8", font=("Segoe UI Semibold", 18), anchor="w"
                 ).pack(fill="x", pady=(0, 10))

    def text(self, text, size=10, colour="#e6e0ee", pady=(0, 8)):
        label = tk.Label(self, text=text, bg="#1e1b24", fg=colour, font=("Segoe UI", size), justify="left",
                         anchor="w", wraplength=690)
        label.pack(fill="x", pady=pady)
        return label

    def steps(self, items):
        box = tk.Frame(self, bg="#28232f", padx=16, pady=12)
        box.pack(fill="x", pady=(2, 10))
        for n, item in enumerate(items, 1):
            row = tk.Frame(box, bg="#28232f")
            row.pack(fill="x", pady=2)
            tk.Label(row, text=f"{n}.", bg="#28232f", fg="#c8a2c8", font=("Segoe UI", 10, "bold"), width=3,
                     anchor="ne").pack(side="left", anchor="n")
            tk.Label(row, text=item, bg="#28232f", fg="#e6e0ee", font=("Segoe UI", 10), justify="left",
                     anchor="w", wraplength=620).pack(side="left", fill="x")
        return box

    def status(self):
        label = tk.Label(self, text="", bg="#1e1b24", fg="#9a90a8", font=("Segoe UI", 10), anchor="w",
                         justify="left", wraplength=690)
        label.pack(fill="x", pady=(4, 0))
        return label

    def say(self, label, text, good=None):
        colour = "#8fd19e" if good else "#ef9a9a" if good is False else "#9a90a8"
        label.config(text=text, fg=colour)

    def background(self, work, done):
        """Run slow work (web requests) without freezing the window.
        The work runs on its own thread; the window checks every 100 ms whether it's finished
        (Tk windows may only be touched from the main thread)."""
        box = []
        threading.Thread(target=lambda: box.append(work()), daemon=True).start()

        def check():
            if box:
                done(box[0])
            else:
                self.after(100, check)
        self.after(100, check)


# ---- 1. Welcome ----------------------------------------------

class WelcomePage(Page):
    def build(self):
        self.title("Welcome to Quill")
        self.text("Quill is a guild scribe for World of Warcraft: Forever. He answers guildies in guild chat, "
                  "greets people, tells jokes, and can learn new answers your officers approve.", 11)
        self.text("This setup is for ONE officer per guild. Guildies don't need it: they just install the "
                  "Quill addon (CurseForge) and type \"quill help\" in guild chat.", 11, "#f1ecf7", (4, 14))
        self.steps([
            "Find World of Warcraft on this PC (and install the addon if it's missing).",
            "Optional: connect Quill to your guild's Discord, so officers can review what he learns.",
            "Optional: let an AI look up answers to questions Quill can't answer yet.",
        ])
        self.text("Quill is free. If you turn on the AI, your guild uses its own Anthropic account and pays "
                  "Anthropic directly - roughly 5 to 10 US cents per question looked up. Nobody else's key is "
                  "ever used, and yours never leaves this PC.", 10, "#b8b0c4", (6, 12))
        self.text(CREDIT, 9, "#9a90a8", (10, 0))


# ---- 2. World of Warcraft ------------------------------------

class WowPage(Page):
    def build(self):
        self.title("Where's World of Warcraft?")
        self.text("Quill reads the notebook WoW saves, so it needs to know where the game lives.")
        self.folders = find_wow_folders()
        if self.state["wow"] is None and self.folders:
            self.state["wow"] = str(self.folders[0])
        row = tk.Frame(self, bg="#1e1b24")
        row.pack(fill="x", pady=(4, 6))
        self.folder_var = tk.StringVar(value=self.state["wow"] or "")
        ttk.Entry(row, textvariable=self.folder_var, font=("Segoe UI", 10)).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Browse…", command=self.browse).pack(side="left", padx=(8, 0))
        self.found = self.text("", 9, "#9a90a8")
        tk.Label(self, text="Which version of the game?", bg="#1e1b24", fg="#e6e0ee", font=("Segoe UI", 10),
                 anchor="w").pack(fill="x", pady=(10, 4))
        self.version_box = ttk.Combobox(self, state="readonly", font=("Segoe UI", 10))
        self.version_box.pack(fill="x")
        self.version_box.bind("<<ComboboxSelected>>", lambda e: self.pick_version())
        self.addon_status = self.status()
        self.install_button = ttk.Button(self, text="Install the Quill addon here", command=self.install)
        self.folder_var.trace_add("write", lambda *a: self.folder_changed())
        self.folder_changed()

    def browse(self):
        chosen = filedialog.askdirectory(title="Pick your World of Warcraft folder")
        if chosen:
            self.folder_var.set(chosen)

    def folder_changed(self):
        folder = self.folder_var.get().strip()
        self.state["wow"] = folder or None
        versions = game_versions(folder) if folder and Path(folder).exists() else []
        if self.folders:
            self.found.config(text=f"Found {len(self.folders)} World of Warcraft install(s) on this PC.")
        else:
            self.found.config(text="Couldn't find WoW automatically - use Browse to pick the folder that holds "
                                   "_forever_ (or similar).")
        self.version_box["values"] = versions
        if versions:
            best = next((v for v in versions if "forever" in v), versions[0])
            self.version_box.set(self.state["version"] if self.state["version"] in versions else best)
        else:
            self.version_box.set("")
        self.pick_version()

    def pick_version(self):
        self.state["version"] = self.version_box.get() or None
        self.install_button.pack_forget()
        if not self.state["version"]:
            self.say(self.addon_status, "No game versions found in that folder yet.", False)
        elif addon_installed(self.state["wow"], self.state["version"]):
            self.say(self.addon_status, "✓ The Quill addon is installed.", True)
        else:
            self.say(self.addon_status, "The Quill addon isn't installed in this version yet.")
            self.install_button.pack(anchor="w", pady=(8, 0))
        self.wizard.refresh()

    def install(self):
        try:
            install_addon(self.state["wow"], self.state["version"])
            self.pick_version()
        except Exception as problem:
            self.say(self.addon_status, f"Couldn't install: {problem}", False)

    def ready(self):
        return bool(self.state["wow"] and self.state["version"])


# ---- 3. Discord? ---------------------------------------------

class DiscordChoicePage(Page):
    def build(self):
        self.title("Connect Quill to Discord?")
        self.text("With Discord, questions Quill can't answer (and things guildies teach him) arrive in a private "
                  "#quill-review channel. An officer approves or corrects them, and Quill learns.", 11)
        self.text("Without Discord, Quill still answers in guild chat, greets people and tells jokes - he just "
                  "doesn't learn, and says \"ask an officer\" when he doesn't know.", 11, "#e6e0ee", (0, 16))
        self.choice = tk.StringVar(value={True: "yes", False: "no"}.get(self.state["discord"], ""))
        ttk.Radiobutton(self, text="Yes - connect to our Discord (about 10 minutes)", value="yes",
                        variable=self.choice, command=self.pick).pack(anchor="w", pady=4)
        ttk.Radiobutton(self, text="No - just the addon, nothing else", value="no",
                        variable=self.choice, command=self.pick).pack(anchor="w", pady=4)
        self.text("You'll need to be able to manage your guild's Discord server (or have someone who can).",
                  9, "#9a90a8", (14, 0))

    def pick(self):
        self.state["discord"] = self.choice.get() == "yes"
        self.wizard.refresh()

    def ready(self):
        return self.state["discord"] is not None


# ---- 4. The Discord bot --------------------------------------

class BotPage(Page):
    def build(self):
        self.title("Make Quill's Discord bot")
        self.text("Quill needs his own bot account in Discord. It takes a few minutes, once:")
        self.steps([
            "Click \"Open the Discord Developer Portal\" below and log in with your normal Discord account.",
            "Click New Application, name it Quill, tick the agreement, click Create.",
            "Left menu: Installation. Set Install Link to None, then Save Changes. (Otherwise the next step "
            "won't save.)",
            "Left menu: Bot. Turn Public Bot OFF, and turn Message Content Intent ON. Save Changes.",
            "Still on Bot: click Reset Token, then Copy. Paste it below. Treat it like a password - "
            "it's Quill's login.",
        ])
        ttk.Button(self, text="Open the Discord Developer Portal",
                   command=lambda: webbrowser.open("https://discord.com/developers/applications")
                   ).pack(anchor="w", pady=(0, 10))
        row = tk.Frame(self, bg="#1e1b24")
        row.pack(fill="x")
        self.token_var = tk.StringVar(value=self.state["token"])
        ttk.Entry(row, textvariable=self.token_var, show="•", font=("Segoe UI", 10)).pack(side="left", fill="x",
                                                                                          expand=True)
        ttk.Button(row, text="Test", command=self.test).pack(side="left", padx=(8, 0))
        self.result = self.status()
        self.warn = tk.Label(self, text="", bg="#1e1b24", fg="#f0c674", font=("Segoe UI", 10), anchor="w",
                             justify="left", wraplength=690)
        self.warn.pack(fill="x")
        if self.state["bot_name"]:
            self.say(self.result, f"✓ Logged in as {self.state['bot_name']}.", True)
        self.token_var.trace_add("write", lambda *a: self.changed())

    def changed(self):
        self.state["bot_name"] = ""
        self.say(self.result, "")
        self.warn.config(text="")
        self.wizard.refresh()

    def test(self):
        token = self.token_var.get().strip()
        self.say(self.result, "Checking…")

        def work():
            try:
                me = discord("/users/@me", token)
                app = discord("/oauth2/applications/@me", token)
                return me, app, None
            except urllib.error.HTTPError as problem:
                return None, None, ("Discord didn't accept that token. On the Bot page click Reset Token "
                                    "and copy the new one." if problem.code == 401 else f"Discord said {problem.code}.")
            except Exception as problem:
                return None, None, f"Couldn't reach Discord: {problem}"

        def done(result):
            me, app, problem = result
            if problem:
                return self.say(self.result, problem, False)
            self.state.update(token=token, bot_name=me["username"], bot_id=me["id"], client_id=app["id"])
            warnings = []
            if not (app.get("flags", 0) & MESSAGE_CONTENT_FLAGS):
                warnings.append("Message Content Intent looks OFF - turn it on (Bot page) or Quill can't "
                                "read officers' replies.")
            if app.get("bot_public"):
                warnings.append("Public Bot is ON - turn it off so strangers can't add Quill to their servers.")
            self.say(self.result, f"✓ Logged in as {me['username']}.", True)
            self.warn.config(text="\n".join("⚠ " + w for w in warnings))      # amber: worked, but fix these
            self.wizard.refresh()

        self.background(work, done)

    def ready(self):
        return bool(self.state["bot_name"])


# ---- 5. Your server, officers and channels -------------------

class ServerPage(Page):
    def build(self):
        self.title("Add Quill to your guild's Discord")
        self.steps([
            "Click \"Invite Quill\" below, pick your guild's server, and click Authorise.",
            "Click \"I've invited him\" - your server should appear in the list.",
            "Pick which role your officers have. Only people with that role can approve things.",
        ])
        buttons = tk.Frame(self, bg="#1e1b24")
        buttons.pack(fill="x", pady=(0, 8))
        url = (f"https://discord.com/oauth2/authorize?client_id={self.state['client_id']}"
               f"&scope=bot&permissions={PERMISSIONS}")
        ttk.Button(buttons, text="Invite Quill", style="Accent.TButton",
                   command=lambda: webbrowser.open(url)).pack(side="left")
        ttk.Button(buttons, text="I've invited him", command=self.load_servers).pack(side="left", padx=(8, 0))
        grid = tk.Frame(self, bg="#1e1b24")
        grid.pack(fill="x", pady=(6, 0))
        for row, label in enumerate(("Server", "Officer role")):
            tk.Label(grid, text=label, bg="#1e1b24", fg="#e6e0ee", font=("Segoe UI", 10), width=12, anchor="w"
                     ).grid(row=row, column=0, sticky="w", pady=4)
        self.server_box = ttk.Combobox(grid, state="readonly", font=("Segoe UI", 10), width=50)
        self.server_box.grid(row=0, column=1, sticky="we", pady=4)
        self.server_box.bind("<<ComboboxSelected>>", lambda e: self.pick_server())
        self.role_box = ttk.Combobox(grid, state="readonly", font=("Segoe UI", 10), width=50)
        self.role_box.grid(row=1, column=1, sticky="we", pady=4)
        self.role_box.bind("<<ComboboxSelected>>", lambda e: self.pick_role())
        grid.columnconfigure(1, weight=1)
        self.make_var = tk.BooleanVar(value=self.state["make_channels"])
        ttk.Checkbutton(self, text="Create Quill's channels for me: #quill, and private #quill-review and "
                                   "#new-members (officers only)", variable=self.make_var,
                        command=lambda: self.state.update(make_channels=self.make_var.get())
                        ).pack(anchor="w", pady=(10, 0))
        self.result = self.status()
        self.servers, self.roles = [], []
        if self.state["server_id"]:
            self.load_servers()

    def load_servers(self):
        self.say(self.result, "Looking…")
        token = self.state["token"]
        self.background(lambda: self._safe(lambda: discord("/users/@me/guilds", token)), self.got_servers)

    def _safe(self, call):
        try:
            return call()
        except Exception as problem:
            return problem

    def got_servers(self, servers):
        if isinstance(servers, Exception) or not servers:
            return self.say(self.result, "Quill isn't in any server yet. Click Invite Quill, pick your server, "
                                         "Authorise, then try again.", False)
        self.servers = servers
        self.server_box["values"] = [s["name"] for s in servers]
        chosen = next((s for s in servers if s["id"] == self.state["server_id"]), servers[0])
        self.server_box.set(chosen["name"])
        self.say(self.result, "")
        self.pick_server()

    def pick_server(self):
        server = next(s for s in self.servers if s["name"] == self.server_box.get())
        self.state.update(server_id=server["id"], server_name=server["name"])
        token = self.state["token"]
        self.background(lambda: self._safe(lambda: discord(f"/guilds/{server['id']}/roles", token)), self.got_roles)

    def got_roles(self, roles):
        if isinstance(roles, Exception):
            return self.say(self.result, f"Couldn't read the roles: {roles}", False)
        self.roles = [r for r in roles if r["name"] != "@everyone" and not r.get("managed")]
        names = [r["name"] for r in sorted(self.roles, key=lambda r: -r["position"])]
        self.role_box["values"] = names
        guess = self.state["officer_role"] or next((n for n in names if "officer" in n.lower()), "")
        self.role_box.set(guess)
        self.pick_role()

    def pick_role(self):
        self.state["officer_role"] = self.role_box.get()
        self.wizard.refresh()

    def ready(self):
        return bool(self.state["server_id"] and self.state["officer_role"])


# ---- 6. The AI ------------------------------------------------

class AiPage(Page):
    def build(self):
        self.title("Let an AI look up answers?")
        self.text("When Quill doesn't know something, an AI (Claude, by Anthropic) can search Wowhead, Warcraft "
                  "Wiki and Blizzard's sites and draft an answer with sources. An officer still checks it before "
                  "Quill ever says it.")
        self.choice = tk.StringVar(value={True: "yes", False: "no"}.get(self.state["ai"], ""))
        ttk.Radiobutton(self, text="Yes - our guild will use its own Anthropic account", value="yes",
                        variable=self.choice, command=self.pick).pack(anchor="w", pady=3)
        ttk.Radiobutton(self, text="No - officers will answer questions themselves", value="no",
                        variable=self.choice, command=self.pick).pack(anchor="w", pady=3)
        self.details = tk.Frame(self, bg="#1e1b24")
        self.pick(initial=True)

    def pick(self, initial=False):
        if not initial:
            self.state["ai"] = self.choice.get() == "yes"
        for child in self.details.winfo_children():
            child.destroy()
        self.details.pack_forget()
        if self.state["ai"]:
            self.details.pack(fill="x", pady=(8, 0))
            self._build_details()
        self.wizard.refresh()

    def _build_details(self):
        box = tk.Frame(self.details, bg="#28232f", padx=16, pady=10)
        box.pack(fill="x")
        for n, item in enumerate([
            "Click \"Open Anthropic Console\", sign up, and add a little credit under Billing (US$5 is plenty "
            "to start - about 50 to 100 questions).",
            "Under Settings → Limits, set a monthly spend limit, so it can never run away.",
            "Under API Keys, click Create Key, name it Quill, copy it (starts sk-ant-) and paste it below.",
        ], 1):
            tk.Label(box, text=f"{n}.  {item}", bg="#28232f", fg="#e6e0ee", font=("Segoe UI", 10),
                     justify="left", anchor="w", wraplength=650).pack(fill="x", pady=2)
        ttk.Button(self.details, text="Open Anthropic Console",
                   command=lambda: webbrowser.open("https://console.anthropic.com")).pack(anchor="w", pady=8)
        row = tk.Frame(self.details, bg="#1e1b24")
        row.pack(fill="x")
        self.key_var = tk.StringVar(value=self.state["ai_key"])
        ttk.Entry(row, textvariable=self.key_var, show="•", font=("Segoe UI", 10)).pack(side="left", fill="x",
                                                                                        expand=True)
        ttk.Button(row, text="Test", command=self.test).pack(side="left", padx=(8, 0))
        self.result = tk.Label(self.details, text="", bg="#1e1b24", fg="#9a90a8", font=("Segoe UI", 10),
                               anchor="w", justify="left", wraplength=690)
        self.result.pack(fill="x", pady=(4, 0))
        if self.state.get("ai_ok"):
            self.say(self.result, "✓ Key works.", True)
        self.key_var.trace_add("write", lambda *a: (self.state.update(ai_ok=False), self.wizard.refresh()))

    def test(self):
        key = self.key_var.get().strip()
        self.say(self.result, "Checking…")

        def done(result):
            ok, message = result
            if ok:
                self.state.update(ai_key=key, ai_ok=True)
            self.say(self.result, ("✓ " if ok else "") + message, ok)
            self.wizard.refresh()

        self.background(lambda: test_ai_key(key), done)

    def ready(self):
        return self.state["ai"] is False or bool(self.state["ai"] and self.state.get("ai_ok"))


# ---- 7. Finish -------------------------------------------------

class FinishPage(Page):
    def build(self):
        self.title("All set")
        if not self.state["discord"]:
            self.text("Quill works on his own in game - nothing else to install. Guildies just need the addon.", 11)
            self.steps([
                "Log into WoW. You should see a purple \"Quill … loaded\" line in chat.",
                "In guild chat, type: quill help",
                "Run this setup again any time if you want to add Discord later.",
            ])
            self.text(CREDIT, 9, "#9a90a8", (14, 0))
            return
        self.text("Here's what Finish will do on this PC:", 11)
        items = [f"Save Quill's settings in {HOME} (the bot token"
                 + (" and AI key" if self.state["ai"] else "") + " stay on this PC only).",
                 f"Use the \"{self.state['officer_role']}\" role on {self.state['server_name']} as officers."]
        if self.state["make_channels"]:
            items.append("Create #quill, and private #quill-review and #new-members (skipped if they exist).")
        items.append("Start Quill Office now, hidden, so the review queue works straight away.")
        self.steps(items)
        self.auto_var = tk.BooleanVar(value=self.state["autostart"])
        ttk.Checkbutton(self, text="Start Quill Office automatically when I log into Windows (recommended)",
                        variable=self.auto_var, command=lambda: self.state.update(autostart=self.auto_var.get())
                        ).pack(anchor="w", pady=(0, 8))
        self.text("Try it after: in guild chat ask Quill something he can't know, then type /reload. "
                  "A card should appear in #quill-review within a minute.", 10, "#b8b0c4")
        self.result = self.status()
        self.text(CREDIT, 9, "#9a90a8", (12, 0))

    def finish(self):
        if not self.state["discord"]:
            self.wizard.destroy()
            return
        self.say(self.result, "Setting up…")
        self.wizard.next_button.state(["disabled"])
        self.background(self._do_setup, self._done)

    def _do_setup(self):
        try:
            save_office(self.state)
            created = make_channels(self.state) if self.state["make_channels"] else []
            set_autostart(self.state["autostart"])
            start_office()
            return True, created
        except Exception as problem:
            return False, str(problem)

    def _done(self, result):
        ok, detail = result
        if ok:
            made = (" Created " + ", ".join("#" + c for c in detail) + ".") if detail else ""
            self.say(self.result, "✓ Done. Quill Office is running." + made + " You can close this window.", True)
            self.wizard.next_button.config(text="Close", command=self.wizard.destroy)
            self.wizard.next_button.state(["!disabled"])
        else:
            self.say(self.result, f"Something went wrong: {detail}", False)
            self.wizard.next_button.state(["!disabled"])


# ---- Saving and channels (no windows - easy to test) ---------

def save_office(state):
    HOME.mkdir(parents=True, exist_ok=True)
    settings = {"server": None, "wow_folder": state["wow"], "server_id": state["server_id"],
                "officer_role": state["officer_role"], "home_channel": "quill", "review_channel": "quill-review",
                "new_members_channel": "new-members", "discord_chat": False}
    (HOME / "settings.json").write_text(json.dumps(settings, indent=2), encoding="utf-8")
    (HOME / "token.txt").write_text(state["token"], encoding="utf-8")
    key_file = HOME / "anthropic_key.txt"
    if state["ai"] and state["ai_key"]:
        key_file.write_text(state["ai_key"], encoding="utf-8")
    else:
        key_file.unlink(missing_ok=True)


def make_channels(state):
    """Create #quill (public) and private #quill-review and #new-members. Skips any that already exist."""
    token, server = state["token"], state["server_id"]
    existing = {c["name"] for c in discord(f"/guilds/{server}/channels", token)}
    roles = discord(f"/guilds/{server}/roles", token)
    officer = next(r for r in roles if r["name"] == state["officer_role"])
    everyone = next(r for r in roles if r["name"] == "@everyone")
    bot_can = VIEW | SEND | EMBED | HISTORY | REACT
    created = []
    for name, private in (("quill", False), ("quill-review", True), ("new-members", True)):
        if name in existing:
            continue
        overwrites = [{"id": state["bot_id"], "type": 1, "allow": str(bot_can), "deny": "0"}]
        if private:
            overwrites += [{"id": everyone["id"], "type": 0, "allow": "0", "deny": str(VIEW)},
                           {"id": officer["id"], "type": 0, "allow": str(VIEW | SEND | HISTORY | REACT), "deny": "0"}]
        discord(f"/guilds/{server}/channels", token, "POST",
                {"name": name, "type": 0, "permission_overwrites": overwrites,
                 "topic": "Quill's officer review queue" if name == "quill-review" else
                          "New members' answers to Quill's questions" if name == "new-members" else
                          "Answers Quill has learned"})
        created.append(name)
    return created


if __name__ == "__main__":
    Wizard().mainloop()
