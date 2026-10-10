# Setting up Quill

Quill is a guild scribe for **World of Warcraft: Forever**. He answers guildies in guild chat, greets people,
cheers level-ups, welcomes new members and tells jokes. With the optional back office, he can learn new
answers that your officers approve, and an AI can help look things up.

*Quill was designed by Ewen and coded by Claude ([claude.ai](https://claude.ai)), Anthropic's AI.*

---

## For guildies: install the addon

That's all a guildie ever needs to do.

1. Install **Quill** from CurseForge, or download the addon zip and unzip it into your game's
   `Interface\AddOns` folder. You should end up with `Interface\AddOns\Quill\Quill.toc`.
2. Restart WoW. On the character screen, click **AddOns** and make sure **Quill** is ticked.
3. Log in. A purple *"Quill … loaded"* line appears in chat.
4. In guild chat, type `quill help`.

Things to say: `quill joke`, `quill <a question>`, `quill teach <something>`, `quill new joke <a joke>`,
`quill be nice to me`. You can also whisper anyone who has Quill: `quill joke`.

Only one copy of Quill talks at a time, however many guildies install it. The copies agree among themselves
who that is.

---

## For one officer per guild: the back office (optional)

Without a back office, Quill still does everything above. He just doesn't learn, and when he doesn't know
something he says *"ask an officer"*.

With the back office:
- Questions Quill can't answer, and things guildies teach him, arrive in a private **#quill-review**
  channel in your Discord.
- An officer approves, corrects or dismisses each one, and Quill learns the approved ones.
- Optionally, an **AI** drafts answers with sources for the officers to check.

**What you need:** a Windows PC that plays WoW (the officer's own), and permission to manage your guild's
Discord server.

### Install

1. Download **QuillSetup.exe** from this repo's **Releases** page and run it.
2. Follow the steps on screen. The wizard:
   - finds World of Warcraft (and installs the addon if it's missing);
   - asks **"Connect Quill to Discord?"** If yes, it walks you through making the bot, checks the token
     works, invites Quill to your server, and creates `#quill`, `#quill-review` and `#new-members` for you;
   - asks **"Let an AI look up answers?"** If yes, it walks you through the Anthropic account, checks the
     key works, and reminds you to set a spending limit;
   - starts **Quill Office** hidden, and with Windows if you tick that box.
3. Test it: in guild chat ask Quill something he can't know, then type `/reload`. A card should appear in
   **#quill-review** within a minute.

### Using it

| In #quill-review | What it does |
| --- | --- |
| ✅ on a question card | Accept the AI's draft answer |
| Reply to a question card | Give your own answer instead |
| ✅ / ❌ on a lesson or joke | Approve or reject it |
| `!announce Wed 19:30 Raid in 30!` | Quill says it in guild chat then (server time); `every Wed …` repeats weekly |
| `!announcements` / `!cancel 2` | List / remove scheduled announcements |

In game, officers can type `/quill hush 30` to quiet Quill for 30 minutes, and `/quill unhush` to undo it.

Approved answers reach the game after the officer's next `/reload` or login. From there they spread to every
guildie's copy of Quill.

### Costs and privacy

- **Quill is free.** The back office runs on your PC; there's no server to rent.
- **The AI is optional and paid by your guild,** on your own Anthropic account: roughly US$0.05–0.10 per
  question looked up. Set a monthly limit in the Anthropic Console. Nobody else's key is ever used, and
  yours never leaves your PC.
- Your bot token and AI key are stored only in `%APPDATA%\QuillOffice` on your PC.

### Troubleshooting

| What you see | What to do |
| --- | --- |
| No card appears in #quill-review | Type `/reload` in game (WoW only saves Quill's notebook on reload or logout), and check the officer PC is on |
| Card says "Couldn't look it up" | The AI account is out of credit, or the key changed. Run QuillSetup again |
| Officers' ✅ does nothing | They need the officer role you picked in setup |
| Quill doesn't answer in game | Type `/quill who` to see which copy is speaking |
| Something else | The log is at `%APPDATA%\QuillOffice\office.log` |
