# Quill, the guild scribe

**Your guild's own scribe, living in guild chat.** Say "quill" and he answers.

## What Quill does

- **Answers guild questions.** Raid times, loot rules, sign-ups, the Discord link: set them once in `QuillGuild.lua`.
- **Greets guildies** coming online, with 55 greetings plus class-flavoured ones. A chance setting keeps it from
  getting spammy.
- **Cheers level-ups** at milestones, and makes a fuss at level 60.
- **Welcomes new members** and whispers them five friendly questions for the officers.
- **Jokes.** `quill joke`, `quill new joke …`, and `quill be nice to me` if his greetings get too cheeky.
- **Learns.** `quill teach …` and unanswered questions go to your officers (with the optional back office).
- **Knows when to be quiet.** Hushable by officers, quiet in raids, never speaks mid-combat, rate-limited.

## Only one Quill talks

Every guildie can install Quill. The copies talk over the game's hidden addon channel and agree on **one speaker**,
so your guild hears one Quill, never twenty. When the speaker logs off, the next takes over.

## Commands

In guild chat: `quill help`, `quill joke`, `quill <a question>`, `quill teach <something>`.
Slash commands: `/quill who`, `/quill about`, and for officers `/quill hush 30`, `/quill unhush`.

## The back office (optional, for one officer)

Want Quill to learn? One officer runs **QuillSetup.exe** (from GitHub) on their own PC. It connects Quill to a
private Discord channel where officers approve answers, and can use an AI to draft them on **your guild's own**
Anthropic account. Guide and download: https://github.com/narx00-au/quill

---

*Quill was designed by Medalin and coded by Claude (claude.ai), Anthropic's AI.*
