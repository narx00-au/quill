# Quill, the guild scribe

A **World of Warcraft: Forever** addon that lives in your guild chat. Say `quill` and he answers.

- Answers your guild's questions: raid times, loot rules, how to sign up, where the Discord is
- Greets guildies coming online (with a chance, so it never gets spammy) and cheers level-ups
- Welcomes new members and whispers them a few friendly questions
- Tells jokes, takes new ones, and can roast you (only if you ask)
- Officers can hush him, and he goes quiet in raids
- Only **one** copy talks, however many guildies install it. The copies sort it out among themselves over the
  game's hidden addon channel.

*Quill was designed by Medalin and coded by Claude ([claude.ai](https://claude.ai)), Anthropic's AI.*

## Players

Install **Quill** from CurseForge, or download `Quill-addon.zip` from [Releases](../../releases) and unzip it into
your game's `Interface\AddOns` folder. Then type `quill help` in guild chat.

## Officers (optional): teach Quill new answers

One officer per guild can run the **back office** on their own Windows PC. Questions Quill can't answer
appear in a private Discord channel; officers approve answers, and Quill learns them. An AI can draft the
answers too, on **your guild's own** Anthropic account (optional, a few cents per question).

Download **QuillSetup.exe** from [Releases](../../releases) and follow the steps. Full guide:
[docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md).

## What's in here

| Folder | What it is |
| --- | --- |
| `addon/Quill` | The addon itself. Edit `QuillGuild.lua` to give Quill your guild's answers. |
| `tools` | The back office: setup wizard, Discord side, and the bridge that reads Quill's notebook |
| `.github/workflows` | Builds `QuillSetup.exe` on GitHub's Windows machines for each release |

## Privacy

The addon never leaves the game: it talks only in guild chat and the guild's hidden addon channel. The back office
keeps your bot token and AI key in `%APPDATA%\QuillOffice` on your PC and sends them nowhere except Discord and
Anthropic.
