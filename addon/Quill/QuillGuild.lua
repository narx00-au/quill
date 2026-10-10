-- ============================================================
--  Quill - YOUR GUILD'S ANSWERS  (the GM fills these in)
--
--  Type the whole answer between the quote marks, exactly as Quill should say it.
--  Anything left as "" makes Quill say "Ask an officer, <name>."
--  {name} gets swapped for whoever asked.
--
--  This file is kept separate so the public version of Quill
--  never publishes your raid times or officer names.
--  After editing: save, then /reload in game.
-- ============================================================

QuillGuild = {
    raidTimes   = "",   -- e.g. "Raids are Wednesday and Sunday at 8pm server time."
    signup      = "",   -- e.g. "Sign up in #raid-signups on Discord, {name}."
    signupRules = "",   -- e.g. "Sign up by the night before. No-shows lose priority."
    loot        = "",   -- e.g. "Loot council. Main spec beats off spec."
    discord     = "",   -- e.g. "Our Discord: discord.gg/xxxx. Quill's answers go in #quill."
    officers    = "",   -- e.g. "Officers are Vex and Grimtusk. GM is Medalin."
    guildBank   = "",   -- e.g. "Ask an officer before taking anything. Donations welcome."
    rules       = "",   -- e.g. "Be decent, don't ninja, full rules in #rules on Discord."
    answersChannel = "",   -- the Discord channel where answers get posted ("" = don't mention Discord)

    -- ---- Greetings when guildies log in ----
    greetings   = true,      -- false = Quill never greets anyone
    mood        = "Funny",   -- "Plain", "Funny", "Sarcastic", "Mean" or "Random"
    allowMean   = false,     -- true lets Quill use the Mean lines (in "Mean" or "Random" mood)
    greetChance = 60,        -- percent chance Quill greets someone who logs in (100 = everyone)
    greetGap    = 8,         -- hours before the same person can be greeted (or skipped) again

    -- ---- Keeping Quill polite ----
    rateLimit   = 3,         -- requests one person can make...
    ratePeriod  = 60,        -- ...in this many seconds, before Quill says "give me a minute"
    quietInRaid = true,      -- Quill doesn't answer in guild chat while the speaker is inside a raid
    holdInCombat = true,     -- in combat, Quill's messages wait until the fight is over

    -- ---- Extras ----
    levelCheers = true,                      -- congratulate guildies on reaching these levels
    levelMilestones = { 10, 20, 30, 40, 50, 60 },
    newMemberQuestions = true,               -- whisper new members 5 quick questions (answers go to #new-members)

    -- No greetings during raids. Server time, 24-hour clock. Days: Sun Mon Tue Wed Thu Fri Sat
    raidHours   = {
        -- { day = "Wed", from = "20:00", to = "23:30" },
    },
}
