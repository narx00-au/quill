# ============================================================
#  Quill - Discord side, version 3
#
#  What this does:
#    1. Logs into Discord as Quill (he goes from grey to green).
#    2. Says hello once in #quill, and answers greetings.
#    3. Posts the in-game notebook (sent up by the bridge) in #quill-review.
#    4. Asks the AI to look up each question (Wowhead, Warcraft Wiki,
#       Blizzard) and adds its draft answer and sources to the card.
#    5. Lets officers accept the draft, reply with their own answer, or
#       approve/reject teach and jokes. Results go to #quill and approved.json.
#
#  Lines starting with # are notes for humans. Python skips them.
# ============================================================

import asyncio
import json
import random
import re
import shutil
import sys
import time
from getpass import getpass
from pathlib import Path

try:
    import discord
    from discord.ext import tasks
except ImportError:
    print("discord.py isn't installed. In PowerShell run:  python -m pip install discord.py")
    input("Press Enter to close.")
    sys.exit(1)

try:
    import anthropic            # the AI that drafts answers (optional - Quill works without it)
except ImportError:
    anthropic = None


# ---- Settings ------------------------------------------------

# Where Quill keeps his files. Normally the folder above tools (C:\Quill, or ~/quill on the server).
# The Quill Office app (other guilds' setup) points QUILL_HOME at its own folder instead.
import os
QUILL_FOLDER = Path(os.environ.get("QUILL_HOME") or Path(__file__).resolve().parent.parent)
TOKEN_FILE = QUILL_FOLDER / "token.txt"   # Quill's password. Never share it.

# settings.json (optional) - written by the setup wizard. Anything missing uses the default here.
try:
    SETTINGS = json.loads((QUILL_FOLDER / "settings.json").read_text(encoding="utf-8"))
except (FileNotFoundError, ValueError):
    SETTINGS = {}

DISCORD_CHAT = SETTINGS.get("discord_chat", False)   # benched: no chat, jokes or hello in Discord
HOME_CHANNEL = SETTINGS.get("home_channel", "quill")                # where approved answers are announced
REVIEW_CHANNEL = SETTINGS.get("review_channel", "quill-review")     # where officers check things (and !announce)
NEW_MEMBERS_CHANNEL = SETTINGS.get("new_members_channel", "new-members")   # new members' answers
OFFICER_ROLE = SETTINGS.get("officer_role", "officer").lower()      # Discord role allowed to approve
SERVER_ID = SETTINGS.get("server_id")                               # only use this Discord server (None = any)

INCOMING = QUILL_FOLDER / "incoming"      # the bridge drops notebook entries here
REVIEW_FILE = QUILL_FOLDER / "review.json"       # what's waiting / decided in #quill-review
POSTED_FILE = QUILL_FOLDER / "posted.json"                     # every note already put on a card - never twice
APPROVED_FILE = QUILL_FOLDER / "approved.json"   # everything officers have approved
BACKUPS = QUILL_FOLDER / "backups"               # hourly snapshots, kept for 14 days
PHRASES_FILE = QUILL_FOLDER / "QuillPhrases.lua"  # the addon's phrasebook - the jokes come from here

# ---- The AI researcher ----
AI_KEY_FILE = QUILL_FOLDER / "anthropic_key.txt"  # the API key. Never share it.
AI_MODEL = "claude-sonnet-5-5"                    # good balance of smart and cheap
AI_MAX_SEARCHES = 3                               # per question - keeps the cost to a few cents
AI_SOURCES = ["wowhead.com", "warcraft.wiki.gg", "worldofwarcraft.blizzard.com", "news.blizzard.com"]
AI_BRIEF = """You research answers for Quill, a helper that answers questions in a World of Warcraft guild's chat.
The guild plays World of Warcraft: Forever (released 4 November 2026; beta from September 2026). Forever is
"Classic+": the original 2004 game expanded with new zones, dungeons, a new race (Skyborne) and class changes.
It is NOT the same as Classic Era, Season of Discovery or retail, so facts from those may be wrong for Forever.

Search for the answer. Prefer pages specifically about Forever (for example wowhead.com/forever). If you can only
find Classic Era or retail information, say so and lower your confidence.

Reply in exactly this format and nothing else:
ANSWER: <the answer as Quill would say it in guild chat: plain text, no links, no markdown, under 220 characters>
CONFIDENCE: <high, medium or low>
NOTES: <one short line for the officers: what you're unsure of, or "none">"""

# Straight from the Day-One Pack. {name} gets swapped for the person's name.
GREETINGS = [
    "Hi {name}.",
    "{name}! What do you need?",
    "Quill reporting for duty. Mostly.",
    "Hey {name}. Ink's ready.",
    "Ah, {name}. I was just writing about you. All good things.",
]


# ---- The token -----------------------------------------------

def get_token():
    """Read the token from token.txt. First time round, ask for it and save it."""
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()
        if token:
            return token

    print("First run: Quill needs his token (Developer Portal > Bot > Reset Token).")
    print("Paste it below and press Enter. Nothing shows on screen while you paste - that's normal.")
    token = getpass("Token: ").strip()
    TOKEN_FILE.write_text(token, encoding="utf-8")
    print(f"Saved to {TOKEN_FILE}. You won't be asked again.\n")
    return token


# ---- Quill himself -------------------------------------------

intents = discord.Intents.default()
intents.message_content = True   # lets Quill read what messages SAY (the switch on the Bot page)
client = discord.Client(intents=intents)
said_hello = False


@client.event
async def on_ready():
    """Runs when Quill has finished logging in."""
    global said_hello
    print(f"Logged in as {client.user}. Quill is ONLINE.")
    if not check_incoming.is_running():
        check_incoming.start()
    if not hourly_backup.is_running():
        hourly_backup.start()
    global ai
    if ai is None:
        ai = make_ai()

    if said_hello or not DISCORD_CHAT:    # only say hello once, and only if Discord chat is on
        return
    said_hello = True

    for server in client.guilds:
        channel = discord.utils.get(server.text_channels, name=HOME_CHANNEL)
        if channel:
            await channel.send("Quill reporting for duty. Mostly.")
            print(f"Said hello in #{HOME_CHANNEL} on {server.name}.")
        else:
            print(f"Couldn't find a #{HOME_CHANNEL} channel on {server.name}.")


# ---- Saving and loading Quill's records ----------------------

def load_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def save_json(path, data):
    temp = path.with_suffix(".tmp")      # write to a temp file first, so a crash can't leave half a file
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)


review = load_json(REVIEW_FILE, {})      # Discord message number -> the notebook entry
approved = load_json(APPROVED_FILE, {"answers": [], "facts": [], "jokes": []})


# ---- How a review card looks ---------------------------------

KINDS = {   # kind: (title, colour, what officers should do)
    "question": ("\u2753 Question from the game", 0x5865F2, "Reply to this message with the answer. \u274c to dismiss."),
    "question+draft": ("\u2753 Question from the game", 0x5865F2,
                       "\u2705 to accept the AI draft \u00b7 reply with your own answer instead \u00b7 \u274c to dismiss."),
    "teach":    ("\U0001F4DA Someone taught Quill something", 0xF1C40F, "\u2705 to approve, \u274c to reject."),
    "joke":     ("\U0001F602 New joke submitted", 0xE67E22, "\u2705 to approve, \u274c to reject."),
}
YES, NO = "\u2705", "\u274c"


def short(text, limit):
    text = (text or "").strip() or "(blank)"
    return text if len(text) <= limit else text[:limit - 1] + "\u2026"


def make_card(entry):
    title, colour, how = KINDS.get(entry["kind"], ("\U0001F4DD Note", 0x95A5A6, "\u274c to dismiss."))
    status = entry.get("status", "waiting")
    if status == "approved":
        colour = 0x2ECC71
    elif status == "rejected":
        colour = 0x7F8C8D

    card = discord.Embed(title=title, description=short(entry["text"], 4000), colour=colour)
    card.add_field(name="From", value=short(entry["name"], 200), inline=True)
    if entry.get("when"):
        card.add_field(name="When", value=f"<t:{int(entry['when'])}:f>", inline=True)
    if entry.get("answer"):
        card.add_field(name="Answer", value=short(entry["answer"], 1000), inline=False)
    if entry.get("ai") == "working":
        card.add_field(name="AI", value="\U0001F50E Looking it up\u2026", inline=False)
    elif entry.get("ai") == "failed":
        card.add_field(name="AI", value=short("Couldn't look it up: " + entry.get("ai_error", "?"), 1000), inline=False)
    if entry.get("draft") and status == "waiting":
        card.add_field(name=f"AI draft (confidence: {entry.get('confidence', '?')})",
                       value=short(entry["draft"], 1000), inline=False)
        if entry.get("notes") and entry["notes"].lower() != "none":
            card.add_field(name="AI notes", value=short(entry["notes"], 1000), inline=False)
    if entry.get("sources"):
        card.add_field(name="Sources", value=short("\n".join(f"<{url}>" for url in entry["sources"]), 1000), inline=False)

    if status == "waiting":
        if entry.get("draft"):
            how = KINDS["question+draft"][2]
        card.set_footer(text=how)
    elif status == "approved":
        verb = "Answered" if entry["kind"] == "question" else "Approved"
        card.set_footer(text=f"{YES} {verb} by {entry['by']}")
    else:
        card.set_footer(text=f"{NO} Rejected by {entry['by']}")
    return card


def channel_named(name):
    for server in client.guilds:
        if SERVER_ID and str(server.id) != str(SERVER_ID):
            continue                            # Quill is in another server too - only use the guild's one
        channel = discord.utils.get(server.text_channels, name=name)
        if channel:
            return channel
    return None


def is_officer(member):
    return any(role.name.lower() == OFFICER_ROLE for role in getattr(member, "roles", []))


# ---- The AI researcher ---------------------------------------

def make_ai():
    if anthropic is None:
        print("AI is off: the anthropic package isn't installed.")
        return None
    try:
        key = AI_KEY_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        print("AI is off: no anthropic_key.txt yet.")
        return None
    print(f"AI is on ({AI_MODEL}, up to {AI_MAX_SEARCHES} searches per question).")
    return anthropic.AsyncAnthropic(api_key=key) if key else None


ai = None


async def ai_research(question):
    """Ask Claude to look the question up. Returns (answer, confidence, notes, sources)."""
    response = await ai.messages.create(
        model=AI_MODEL,
        max_tokens=1024,
        system=AI_BRIEF,
        tools=[{"type": "web_search_20250305", "name": "web_search",
                "max_uses": AI_MAX_SEARCHES, "allowed_domains": AI_SOURCES}],
        messages=[{"role": "user", "content": f"A guildie asked in game: {question}"}],
    )
    text, sources = "", []
    for block in response.content:
        if block.type == "text":
            text += block.text
            for cite in getattr(block, "citations", None) or []:
                url = getattr(cite, "url", None)
                if url and url not in sources:
                    sources.append(url)

    def field(label):
        found = re.search(label + r":\s*(.+)", text)
        return found.group(1).strip() if found else ""

    answer = field("ANSWER") or text.strip()
    return answer, (field("CONFIDENCE") or "?").lower(), field("NOTES"), sources[:3]


async def draft_answer(card, entry):
    """Runs in the background after a question card is posted."""
    entry["ai"] = "working"
    await card.edit(embed=make_card(entry))
    try:
        answer, confidence, notes, sources = await ai_research(entry["text"])
        entry.update(ai="done", draft=answer, confidence=confidence, notes=notes, sources=sources)
        print(f"AI drafted an answer for {entry['name']} ({confidence} confidence)")
    except Exception as problem:
        entry.update(ai="failed", ai_error=str(problem)[:300])
        print(f"AI couldn't answer: {problem}")
    save_json(REVIEW_FILE, review)
    if entry["status"] == "waiting":
        await card.edit(embed=make_card(entry))
        if entry.get("draft"):
            await card.add_reaction(YES)          # officers can now accept the draft


async def approve_question(entry, answer, officer, card):
    """Record an answer, update the card and tell #quill."""
    entry.update(status="approved", by=officer, answer=answer)
    approved["answers"].append({"question": entry["text"], "answer": answer, "asker": entry["name"],
                                "by": officer, "sources": entry.get("sources", []) if answer == entry.get("draft") else [],
                                "patch": entry.get("patch", ""), "when": int(time.time())})
    save_json(APPROVED_FILE, approved)
    save_json(REVIEW_FILE, review)
    await card.edit(embed=make_card(entry))
    home = channel_named(HOME_CHANNEL)
    if home:
        line = f"\u2753 **{entry['name']}** asked: {entry['text']}\n\U0001F4AC {answer}"
        if answer == entry.get("draft") and entry.get("sources"):
            line += f"\nSource: <{entry['sources'][0]}>"
        await home.send(line)
    print(f"{officer} answered {entry['name']}'s question")


# ---- Picking up what the bridge sent -------------------------

@tasks.loop(seconds=10)
async def check_incoming():
    INCOMING.mkdir(exist_ok=True)
    channel = channel_named(REVIEW_CHANNEL)
    if channel is None:
        return
    for path in sorted(INCOMING.glob("*.json")):
        if time.time() - path.stat().st_mtime < 3:      # still arriving - next round
            continue
        entries = load_json(path, [])
        path.unlink()                    # take the file first: a hiccup below must never post the batch again
        posted = set(load_json(POSTED_FILE, []))
        posted |= {f"{e.get('when')}|{e.get('name')}|{e.get('kind')}|{e.get('text')}"   # cards from before this list
                   for e in review.values() if isinstance(e, dict)}
        for entry in entries:
            key = f"{entry.get('when')}|{entry.get('name')}|{entry.get('kind')}|{entry.get('text')}"
            if key in posted:
                print(f"Skipped a repeat: {entry.get('kind')} from {entry.get('name')}")
                continue
            try:
                await post_card(channel, entry)
            except Exception as problem:             # one bad card mustn't stop the rest
                print(f"Couldn't post a {entry.get('kind')} from {entry.get('name')}: {problem}")
                continue
            posted.add(key)
            save_json(POSTED_FILE, sorted(posted))


async def post_new_member(entry):
    """A new member answered Quill's questions: post their answers in #new-members."""
    channel = channel_named(NEW_MEMBERS_CHANNEL)
    if channel is None:
        print(f"No #{NEW_MEMBERS_CHANNEL} channel - new member answers for {entry['name']} not posted")
        return
    card = discord.Embed(title=f"\U0001F44B New member: {entry['name']}", colour=0x3498DB)
    for part in (entry.get("text") or "").split(" | "):
        field, _, answer = part.partition(": ")
        if answer:
            card.add_field(name=short(field, 200), value=short(answer, 1000), inline=False)
    if entry.get("when"):
        card.add_field(name="Joined", value=f"<t:{int(entry['when'])}:f>", inline=False)
    await channel.send(embed=card)
    print(f"Posted new member answers for {entry['name']}")


async def post_card(channel, entry):
    """Put one notebook entry in #quill-review as a card, ready for officers."""
    if entry.get("kind") == "newmember":
        return await post_new_member(entry)
    entry["status"] = "waiting"
    card = await channel.send(embed=make_card(entry))
    if entry["kind"] in ("teach", "joke"):
        await card.add_reaction(YES)
    await card.add_reaction(NO)
    review[str(card.id)] = entry
    save_json(REVIEW_FILE, review)
    print(f"Posted a {entry['kind']} from {entry['name']} to #{REVIEW_CHANNEL}")
    if entry["kind"] == "question" and ai:
        asyncio.create_task(draft_answer(card, entry))


# ---- Hourly backup --------------------------------------------
# Every hour, copy what Quill has learned into backups/<date>_<hour>/.
# Snapshots older than 14 days are tidied away.

@tasks.loop(hours=1)
async def hourly_backup():
    folder = BACKUPS / time.strftime("%Y-%m-%d_%H00")
    folder.mkdir(parents=True, exist_ok=True)
    for path in (APPROVED_FILE, REVIEW_FILE):
        if path.exists():
            shutil.copy2(path, folder / path.name)
    cutoff = time.time() - 14 * 24 * 3600
    for old in BACKUPS.iterdir():
        if old.is_dir() and old.stat().st_mtime < cutoff:
            shutil.rmtree(old)
    print(f"Backed up what Quill knows to {folder}")


# ---- Officers deciding ---------------------------------------

@client.event
async def on_raw_reaction_add(payload):
    """Runs when anyone adds a reaction anywhere Quill can see."""
    if payload.user_id == client.user.id:
        return
    entry = review.get(str(payload.message_id))
    emoji = str(payload.emoji)
    if not entry or entry["status"] != "waiting" or emoji not in (YES, NO):
        return
    if not is_officer(payload.member):
        return
    officer = payload.member.display_name
    home = channel_named(HOME_CHANNEL)
    channel = client.get_channel(payload.channel_id)

    if emoji == YES and entry["kind"] == "question":
        if not entry.get("draft"):
            return                                      # nothing to accept yet - reply with an answer instead
        card = await channel.fetch_message(payload.message_id)
        await approve_question(entry, entry["draft"], officer, card)
        return

    if emoji == YES:
        entry.update(status="approved", by=officer)
        record = {"text": entry["text"], "author": entry["name"], "by": officer, "when": int(time.time())}
        if entry["kind"] == "joke":
            approved["jokes"].append(record)
            if home:
                await home.send(f"\U0001F602 New joke by **{entry['name']}**: {entry['text']}")
        else:
            approved["facts"].append(record)
            if home:
                await home.send(f"\U0001F4DA Quill learned something from **{entry['name']}**: {entry['text']}")
        save_json(APPROVED_FILE, approved)
    else:
        entry.update(status="rejected", by=officer)

    save_json(REVIEW_FILE, review)
    card = await channel.fetch_message(payload.message_id)
    await card.edit(embed=make_card(entry))
    print(f"{officer} {entry['status']} a {entry['kind']} from {entry['name']}")


async def handle_answer(message):
    """An officer replied to a question card: that reply is the answer."""
    entry = review.get(str(message.reference.message_id))
    if not entry or entry["kind"] != "question" or entry["status"] != "waiting":
        return
    if not is_officer(message.author):
        await message.reply("Only officers can answer these.", delete_after=10)
        return

    card = await message.channel.fetch_message(message.reference.message_id)
    await approve_question(entry, message.content, message.author.display_name, card)
    await message.add_reaction(YES)



# ---- Jokes ---------------------------------------------------
# The starter jokes live in the addon's phrasebook, so there's only one list to edit.

def starter_jokes():
    try:
        text = PHRASES_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ["Why does Quill tell such bad jokes? Because nobody copied the phrasebook to the server."]
    block = re.search(r"QuillPhrases\.jokes\s*=\s*\{(.*?)\n\}", text, re.S)
    found = re.findall(r'"((?:\\.|[^"\\])*)"', block.group(1)) if block else []
    return [joke.replace('\\"', '"') for joke in found]


def any_joke():
    jokes = starter_jokes()
    guild = approved.get("jokes", [])
    if guild and random.randrange(len(jokes) + len(guild)) >= len(jokes):
        joke = random.choice(guild)
        return f"Joke by {joke['author']}: {joke['text']}"
    return random.choice(jokes)


# ---- Scheduled announcements (!announce in #quill-review) ----
# Quill can't be told things live - the game only reads new files at /reload or login.
# So officers schedule them: every copy of Quill learns the schedule and the speaker says it on time.

DAY_NAMES = {"mon": "Mon", "monday": "Mon", "tue": "Tue", "tues": "Tue", "tuesday": "Tue", "wed": "Wed",
             "wednesday": "Wed", "thu": "Thu", "thur": "Thu", "thurs": "Thu", "thursday": "Thu", "fri": "Fri",
             "friday": "Fri", "sat": "Sat", "saturday": "Sat", "sun": "Sun", "sunday": "Sun"}
ANNOUNCE_HELP = ("Try: `!announce Wed 19:30 Raid in 30, get your flasks` (once) or "
                 "`!announce every Wed 19:30 Raid in 30` (weekly). Times are server time. "
                 "`!announcements` lists them, `!cancel 2` removes number 2.")


def parse_clock(text):
    """'19:30', '7:30pm', '7pm' -> '19:30' (or None)."""
    found = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", text.strip().lower())
    if not found:
        return None
    hour, minute, half = int(found.group(1)), int(found.group(2) or 0), found.group(3)
    if half == "pm" and hour < 12:
        hour += 12
    if half == "am" and hour == 12:
        hour = 0
    if hour > 23 or minute > 59 or (not half and not found.group(2)):
        return None
    return f"{hour:02d}:{minute:02d}"


async def handle_command(message):
    if not is_officer(message.author):
        await message.reply("Only officers can do that.", delete_after=10)
        return
    words = message.content.split()
    command = words[0].lower()
    announcements = approved.setdefault("announcements", [])

    if command == "!announce":
        rest = words[1:]
        repeating = bool(rest) and rest[0].lower() == "every"
        if repeating:
            rest = rest[1:]
        day = DAY_NAMES.get(rest[0].lower().strip(",")) if rest else None
        clock = parse_clock(rest[1]) if len(rest) > 1 else None
        text = " ".join(rest[2:]).strip()
        if not day or not clock or not text:
            await message.reply("I didn't catch that. " + ANNOUNCE_HELP)
            return
        if len(text) > 240:
            await message.reply(f"That's {len(text)} characters - guild chat takes about 240. Shorten it a bit?")
            return
        announcements.append({"id": str(int(time.time())), "day": day, "time": clock, "text": text,
                              "repeating": repeating, "by": message.author.display_name, "when": int(time.time())})
        approved["changed"] = int(time.time())
        save_json(APPROVED_FILE, approved)
        when = f"every {day} at {clock}" if repeating else f"next {day} at {clock}"
        await message.reply(f"\U0001F4E3 Got it. {when} (server time) Quill will say: \"{text}\"\n"
                            "It reaches the game at the officer PC's next `/reload` or login, and goes out "
                            "if anyone with Quill is online then.")
    elif command == "!announcements":
        if not announcements:
            await message.reply("No announcements scheduled. " + ANNOUNCE_HELP)
            return
        lines = [f"**{n}.** {'every' if a['repeating'] else 'next'} {a['day']} {a['time']}: {a['text']} "
                 f"*(by {a['by']})*" for n, a in enumerate(announcements, 1)]
        await message.reply("\n".join(lines))
    elif command == "!cancel":
        number = int(words[1]) if len(words) > 1 and words[1].isdigit() else 0
        if not 1 <= number <= len(announcements):
            await message.reply("Which one? `!announcements` shows the numbers.")
            return
        gone = announcements.pop(number - 1)
        approved["changed"] = int(time.time())
        save_json(APPROVED_FILE, approved)
        await message.reply(f"Cancelled: {gone['day']} {gone['time']}: {gone['text']}")
    else:
        await message.reply(ANNOUNCE_HELP)


# Words that count as saying hello. Lowercase, no punctuation.
HELLO_WORDS = {"hi", "hello", "hey", "hiya", "yo", "sup", "gday", "howdy", "morning", "evening"}


def tidy(text):
    """'G'day, Quill!' becomes ['gday', 'quill'] - lowercase words, no punctuation."""
    text = text.lower().replace("'", "")
    for mark in ",.!?:;-()\"":
        text = text.replace(mark, " ")
    return text.split()


@client.event
async def on_message(message):
    """Runs every time anyone posts anywhere Quill can see."""
    if message.author.bot:  # never reply to bots, including himself
        return

    channel_name = getattr(message.channel, "name", None)    # private messages have no name
    if channel_name == REVIEW_CHANNEL:
        if message.content.startswith("!"):     # !announce, !announcements, !cancel
            await handle_command(message)
        elif message.reference:                 # a reply to one of the cards
            await handle_answer(message)
        return                                  # no chit-chat in the officers' channel

    if not DISCORD_CHAT:                        # benched - Quill only works in game
        return

    words = tidy(message.content)
    greeted = any(word in HELLO_WORDS for word in words)
    named = "quill" in words or client.user in message.mentions
    name = message.author.display_name

    # "quill new joke <joke>" - goes to the officers, same as in game
    lowered = message.content.lower()
    if named and "new joke" in lowered:
        joke = message.content[lowered.index("new joke") + len("new joke"):].strip(" :,-")
        review_channel = channel_named(REVIEW_CHANNEL)
        if not joke:
            await message.reply("I'm all ears. Try: quill new joke <your joke>")
        elif review_channel:
            await post_card(review_channel, {"kind": "joke", "name": name, "text": joke, "when": int(time.time())})
            await message.reply("Noted. The officers will judge it. Harshly.")
        return

    # "quill, tell us a joke"
    if named and ("joke" in words or "jokes" in words):
        await message.channel.send(any_joke())
        return
    in_home = channel_name == HOME_CHANNEL
    just_hello = len(words) == 1 and greeted       # a bare "hi" or "hello"

    if (greeted and named) or (in_home and just_hello) or (named and len(words) <= 1):
        reply = random.choice(GREETINGS).format(name=name)
        await message.channel.send(reply)
        print(f"{name}: {message.content}")
        print(f"Quill: {reply}\n")


# ---- Start ---------------------------------------------------

def main():
    token = get_token()
    try:
        client.run(token, log_handler=None)
    except discord.LoginFailure:
        TOKEN_FILE.unlink(missing_ok=True)
        print("\nDiscord rejected that token. I've deleted token.txt.")
        print("Get a fresh one (Bot page > Reset Token) and run Quill again.")
    except discord.PrivilegedIntentsRequired:
        print("\nMessage Content Intent is switched off.")
        print("Developer Portal > Quill > Bot > turn on Message Content Intent > Save Changes, then run Quill again.")
    if sys.stdin and sys.stdin.isatty():   # only wait for Enter when a person is watching
        input("\nPress Enter to close.")


if __name__ == "__main__":
    main()
