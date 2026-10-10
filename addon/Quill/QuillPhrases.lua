-- ============================================================
--  Quill - THE PHRASEBOOK  (everything Quill can say)
--  Straight from the Day-One Pack. Edit freely, then /reload.
--  {name} = whoever is talking to Quill.
-- ============================================================

QuillPhrases = {}

QuillPhrases.help = {
    "Hi {name}, I'm Quill, the guild scribe. Start with \"quill\", \"hey quill\" or \"yo quill\" - or end a question with my name - and I'll listen.",
    "Ask me a question, say \"joke\" for a joke, \"signup\" for raids, \"teach\" to teach me something, or \"new joke\" to submit one.",
    "If I don't know something, I'll find out{where}. Everything I learn gets checked by the officers first.",
}

-- Ways to get Quill's attention at the START of a message (lowercase, no punctuation - "G'day, Quill!" counts as "gday quill").
-- firm = true: anything after it that Quill doesn't know goes to the officers.
-- Without firm, only things that look like questions do (so "yo quill nice one" doesn't bother anyone).
-- Also always works: a question ending in his name - "what time is raid, quill?"
QuillPhrases.wakeWords = {
    { words = "hey quill", firm = true },
    { words = "ok quill", firm = true },
    { words = "okay quill", firm = true },
    { words = "excuse me quill", firm = true },
    { words = "dear quill", firm = true },
    { words = "hey scribe", firm = true },
    { words = "hey quil", firm = true },
    { words = "quil" },
    { words = "quill" },
    { words = "hi quill" },
    { words = "hello quill" },
    { words = "hiya quill" },
    { words = "yo quill" },
    { words = "oi quill" },
    { words = "ay quill" },
    { words = "sup quill" },
    { words = "gday quill" },
    { words = "morning quill" },
    { words = "evening quill" },
    { words = "mr quill" },
    { words = "mister quill" },
    { words = "quilly" },
    { words = "scribe" },
}

-- Ways people ask for things. Quill looks for these words after his name.
-- If they say what they want but not the thing itself ("I want you to learn something"),
-- Quill asks, and their next message is taken as the lesson or joke.
QuillPhrases.intents = {
    newJoke = { "new joke", "i have a joke", "ive got a joke", "i got a joke", "heres a joke", "joke for you",
                "hear this joke", "hear a joke", "submit a joke", "add a joke",
                "teach you a joke", "tell you a joke", "learn a joke", "remember this joke", "know this joke" },
    teach   = { "teach", "learn", "remember", "note", "write down", "write this down", "did you know", "fyi",
                "fun fact", "til", "add this", "record this", "save this",
                "remember that", "pro tip", "heres a tip", "for the record", "just so you know" },
    help    = { "help", "what can you do", "commands", "how do i use you", "how does this work", "what do you do",
                "how do you work", "how do i talk to you", "what do you know", "list commands", "options", "halp" },
    joke    = { "joke", "jokes", "something funny", "make me laugh", "cheer me up", "tell me something funny",
                "tell me a joke", "got any jokes", "say something funny", "entertain me", "make me smile",
                "im sad", "i am sad", "pun", "dad joke" },
}

QuillPhrases.standard = {
    unknown   = "Not sure, {name}. I'll find out{where}.",
    teach     = "Ooh, thanks {name}. Sending it to the officers to check.",
    newJoke   = "Noted, {name}. The officers will judge it. Harshly.",
    askOfficer = "Ask an officer, {name}.",
    busy      = "Busy right now, {name}. You're {place} in line.",
    beNice    = "Fine, {name}. Nice lines only for you from now on. Say \"hey quill, roast me\" to undo it.",
    roastMe   = "Roasting back on, {name}. You asked for this.",
    emptyTeach = "Teach me what, {name}? Try: hey quill, teach <the thing>",
    emptyJoke  = "I'm all ears, {name}. Try: hey quill, new joke <your joke>",
    slowDown   = "Easy, {name}. Give me a minute.",
    askLesson  = "Go on then, {name}. What should I learn? Just type it next.",
    askJoke    = "Go on, {name}, let's hear it. Just type it next.",
    cancelled  = "No worries, {name}.",
}

-- Small talk. Quill picks one line at random and never the same one twice in a row.
-- "words" are what the player might say (lowercase, no punctuation).
QuillPhrases.smallTalk = {
    {
        words = { "hi", "hello", "hey", "yo", "sup", "hiya", "heya", "howdy", "gday", "oi", "o",
                  "morning", "good morning", "evening", "good evening", "afternoon", "greetings" },
        lines = { "Hi {name}.", "{name}! What do you need?", "Quill reporting for duty. Mostly.",
                  "Hey {name}. Ink's ready.", "Ah, {name}. I was just writing about you. All good things." },
    },
    {
        words = { "thanks", "thank you", "ty", "thx", "cheers", "ta", "thanks heaps", "much appreciated",
                  "appreciate it", "cheers mate" },
        lines = { "Any time, {name}.", "That's what I'm here for.", "Put it on my tab.",
                  "No worries, {name}.", "Happy to help. Tell your friends." },
    },
    {
        words = { "good night", "goodnight", "gn", "night", "nn", "night all", "off to bed", "bed time",
                  "bedtime", "sleep time" },
        lines = { "Night {name}. Don't log out in the fire.", "Sleep well. The quests will still be there.",
                  "Night {name}. I'll guard your loot. Probably.", "Rest up, {name}. Raid needs you sharp.",
                  "Off you go. Rested XP won't earn itself." },
    },
    {
        words = { "are you a bot", "you a bot", "a bot", "robot", "are you a robot", "are you real", "are you ai", "are you an ai",
                  "are you human", "is this a bot", "are you alive" },
        lines = { "I prefer \"enthusiastic scribe\".", "I'm an addon with ambitions.", "Technically. Emotionally, no.",
                  "Beep boop. Kidding. Mostly.", "A bot? I'm a whole Quill, {name}." },
    },
    {
        words = { "love you", "love ya", "ily", "luv you", "marry me", "be my friend" },
        lines = { "I know.", "Steady on, {name}. We've only just met.", "That's sweet. Still not lending you gold.",
                  "Noted in the guild records.", "Aww. Back to work though." },
    },
    {
        words = { "youre useless", "you are useless", "useless", "bad bot", "stupid", "dumb",
                  "youre trash", "you are trash", "shut up", "stfu" },
        lines = { "Harsh but fair. Teach me something then.", "I'm a scribe, not a miracle worker.",
                  "Noted. Filed under \"feedback\".", "Bold words from someone who pulled earlier.",
                  "You say that now. Wait until raid signups." },
    },
    {
        words = { "we wiped", "wiped", "wipe" },
        lines = { "Happens to the best of us. Also to this guild.", "Run back, the boss missed you.",
                  "Repair bills are character building.", "I've written that down as a \"learning attempt\".",
                  "Same time next pull?" },
    },
    {
        words = { "how are you", "how r u", "hows it going", "how you going", "how is it going",
                  "how are you doing", "hows your day", "whats up", "what is up", "wassup", "how ya going" },
        lines = { "Ink's full, quill's sharp. Can't complain.", "Better than whoever just pulled that.",
                  "Busy. Someone keeps asking me questions.", "Good, {name}. You?",
                  "Living the dream. A very small, inky dream." },
    },

    -- From here: short chat-speak. maxWords = only when the message is short, so "sorry, where is the bank?"
    -- still gets treated as a question.
    {
        words = { "good bot", "good job", "well done", "nice one", "legend", "you legend", "love it", "great job",
                  "awesome", "you rock", "best bot" },
        maxWords = 5,
        lines = { "I'll pretend I didn't hear that. No I won't, I'm writing it down.", "Finally, some recognition.",
                  "Thanks {name}. Tell the officers, they never say that.", "Framing that one.",
                  "Stop it, I'll get ink everywhere." },
    },
    {
        words = { "lol", "lmao", "haha", "hahaha", "hehe", "rofl", "lul", "kek", "xd" },
        maxWords = 4,
        lines = { "Glad someone appreciates me.", "I'm here all week. Literally, I can't leave.",
                  "Laughing at me or with me, {name}?", "Tip your scribe.", "I'll be here till the next patch." },
    },
    {
        words = { "brb", "afk", "back soon", "back in a bit", "one sec", "be right back" },
        maxWords = 5,
        lines = { "I'll hold your spot. Not your loot.", "Go on. I'll keep the seat warm.",
                  "Noted. Don't stand in anything while you're gone.", "Take your time, {name}.",
                  "I'll tell them you said hi." },
    },
    {
        words = { "im back", "i am back", "back now", "and im back", "wb" },
        maxWords = 4,
        lines = { "Welcome back, {name}.", "Missed you. Mostly.", "Back already? Nothing exploded. Yet.",
                  "Good, the guild was getting quiet.", "There you are, {name}." },
    },
    {
        words = { "bye", "cya", "see ya", "see you", "gtg", "g2g", "bb", "laters", "catch you later",
                  "logging off", "logging out", "heading off", "im off", "peace" },
        maxWords = 5,
        lines = { "See you, {name}.", "Off you go. I'll keep the ink warm.", "Bye {name}. Log out at an inn.",
                  "Later, {name}. Don't forget your rested XP.", "Safe travels, {name}." },
    },
    {
        words = { "gg", "good game", "gg wp", "ggwp", "well played", "wp" },
        maxWords = 4,
        lines = { "GG. I'll write it up as a victory either way.", "Well played, {name}.",
                  "Noted in the history books. Spelt correctly, even.", "GG. Same time tomorrow?" },
    },
    {
        words = { "ding", "dinged", "i dinged", "just dinged", "leveled up", "levelled up", "i leveled", "i levelled" },
        maxWords = 6,
        lines = { "Grats {name}! Another level, another set of bags to complain about.", "Ding! Congrats {name}.",
                  "Nice one {name}. I've updated the records.", "Grats! Go spend your gold on training.",
                  "Ding! Look at you go, {name}." },
    },
    {
        words = { "congrats", "congratulations", "gz", "grats", "gratz", "grz", "congratz" },
        maxWords = 4,
        lines = { "Grats from me too!", "Seconded. Grats!", "Writing it in the guild records now.",
                  "Grats! Someone fetch the confetti." },
    },
    {
        words = { "i died", "just died", "died again", "rip", "rip me", "i keep dying" },
        maxWords = 6,
        lines = { "Spirit healer's that way. Mind the res sickness.", "F. Run back, {name}.",
                  "Happens to the best of us. Also to you.", "I'll note it as a strategic lie-down.",
                  "Repair bill incoming." },
    },
    {
        words = { "im bored", "i am bored", "bored", "nothing to do" },
        maxWords = 6,
        lines = { "Fish. Nobody's ever bored while fishing. Mostly asleep.", "Run a dungeon, someone's always LFG.",
                  "Level a profession. Your bags will thank you.", "Go explore. There's a lot of map out there, {name}.",
                  "Tell me a joke then. Say \"quill new joke\"." },
    },
    {
        words = { "sorry", "my bad", "soz", "oops", "apologies" },
        maxWords = 4,
        lines = { "All forgiven. Mostly.", "Noted, {name}. Lightly.", "Don't worry about it.",
                  "I've already forgotten. Scribes are good at that. Wait, no we're not." },
    },
    {
        words = { "who are you", "what are you", "who made you", "who created you", "who coded you", "who wrote you",
                  "whats your name", "what is your name" },
        lines = { "I'm Quill, the guild scribe. I answer questions, keep notes and tell bad jokes.",
                  "Quill. Guild scribe. Say \"quill help\" to see what I do.",
                  "An officer dreamt me up and Claude, an AI, wrote me. Type /quill about for the details." },
    },
    {
        words = { "good luck", "gl", "gl hf", "glhf" },
        maxWords = 4,
        lines = { "Good luck! Don't stand in the fire.", "You'll be fine. Probably.", "Good luck, {name}. I believe in you. Mostly." },
    },
}

-- Guild questions. "key" points at the matching answer in QuillGuild.lua.
-- Checked in this order, so "signup rules" is caught before plain "signup".
QuillPhrases.guildQuestions = {
    { key = "signupRules", words = { "signup rules", "sign up rules" } },
    { key = "raidTimes",   words = { "raid times", "raid time", "when is raid", "when are raids", "when do we raid",
                                               "when raid", "raid tonight", "is there raid", "is there a raid", "raid schedule",
                                               "what time is raid", "what time raid", "raid days", "next raid",
                                               "when is the next raid", "when do raids start", "are we raiding" } },
    { key = "signup",      words = { "signup", "sign up", "sign me up", "signups", "sign ups",
                                               "how do i sign", "join the raid", "get in raid", "get into raid" } },
    { key = "loot",        words = { "loot rules", "loot", "loot system", "dkp", "loot council",
                                               "soft res", "soft reserve", "softres", "who gets loot" } },
    { key = "discord",     words = { "discord", "discord link", "voice chat", "comms" } },
    { key = "officers",    words = { "officers", "officer", "in charge", "gm", "guild leader",
                                               "guild master", "guildmaster", "who runs the guild", "who do i ask", "leadership" } },
    { key = "guildBank",   words = { "guild bank", "gbank", "guildbank", "guild vault", "bank alt" } },
    { key = "rules",       words = { "guild rules", "rules", "code of conduct" } },
}

QuillPhrases.jokes = {
    "A warrior, a priest and a rogue walk into a bar. The warrior charges the barman, the priest heals him, and the rogue was there the whole time.",
    "What's the difference between a hunter and a toddler? The toddler eventually stops pulling.",
    "Why do gnomes always stand in the fire? From down there it's the only thing they can see.",
    "How do you know a paladin's in trouble? You don't. He's already bubbled and hearthed.",
    "Why did the druid fail his driving test? Kept shifting at the wrong time.",
    "What does a healer call a DPS standing in the fire? A volunteer.",
    "Why don't tauren play hide and seek? Ever tried hiding a cow behind a bush?",
    "Why was the Forsaken so calm on progression night? Nothing gets under his skin. There isn't much left.",
    "What did the priest say to the dead tank? \"I was in range. Were you?\"",
    "Why are tanks great at parties? They always pull a crowd. Then complain nobody's following.",
    "How does a dwarf apologise? He buys the next round. How does he say thanks? Same answer.",
    "Why is the guild bank always empty? Same reason my fridge is. Someone \"just needed one thing\".",
    "Why don't the Skyborne worry about fall damage? Bold of you to assume they've ever looked down.",
    "What's an orc's favourite music? Heavy metal. Plate only.",
    "Why did the raid leader cry? Someone asked \"what's the strat?\" on the last pull of the night.",
    "Why don't shamans ever get lost? They leave a totem every ten metres.",
    "Why do mages never pay for lunch? They conjure it, then charge you for water.",
    "How many rogues does it take to change a lightbulb? Nobody knows. Nobody saw them.",
    "What's a warlock's favourite chore? Taking out the soul shards. There's always a bag full.",
    "Why did the hunter's pet apply for a transfer? Tired of being blamed for the hunter's pulls.",
    "How do you make a warrior read the boss guide? You can't. You can only explain it to him afterwards, at the spirit healer.",
    "Why did the gnome get the job as raid leader? Everyone agreed he'd never let it go to his head. It's too far up.",
    "What's the scariest sound in a dungeon? \"Hang on, I'll just grab that pack too.\"",
    "Why does Quill tell such bad jokes? Because you lot keep teaching me them.",
}


-- ---- Greeting guildies who log in ----------------------------
-- Quill works through all of these before repeating one. In Funny/Sarcastic/Mean mood,
-- about 1 login in 3 gets a class line instead (see classGreetings below).
QuillPhrases.greetings = {
    "Welcome back, {name}.",
    "{name} is online. Hide the guild bank.",
    "Look who it is. Hi {name}.",
    "{name}! The guild missed you. Mostly.",
    "Hey {name}, welcome back to Azeroth.",
    "Welcome back, {name}. The guild's been suspiciously quiet without you.",
    "{name} has entered the chat. Act natural, everyone.",
    "Ah, {name}. Right on time. For what, we're not sure.",
    "{name} is back! Someone warn the auction house.",
    "Evening, {name}. Or morning. I'm a quill, I don't own a clock.",
    "Look who logged in. Hi {name}, mind the fire.",
    "{name}'s online. Quick, everyone look busy.",
    "Welcome back, {name}. Your bags are exactly as full as you left them.",
    "Hey {name}! Did you bring snacks? You never bring snacks.",
    "{name} has arrived. Guild average just went up. Slightly.",
    "Oh good, {name}. I was running out of people to write about.",
    "Welcome back, {name}. I kept your seat warm. Metaphorically. I'm a quill.",
    "Hail, {name}! Azeroth missed you. Well, the murlocs did.",
    "{name} is here. Somebody put the kettle on.",
    "Welcome back, {name}. Hearthstone's on cooldown, so you're stuck with us.",
    "There they are! Hi {name}.",
    "{name} logged in. Guild records updated: \"still alive\".",
    "G'day {name}. Pull up a chair, mind the ogre.",
    "Welcome back, {name}. Your repair bill is in the mail.",
    "{name}! Just in time to hear someone ask where the trainer is.",
    "Hey {name}. The guild bank says hello. It's lonely in there.",
    "{name} is online. Raid leader, start sweating.",
    "Ah, {name}. I wrote you a welcome. This is it. You're reading it.",
    "Welcome back, {name}. Nothing exploded while you were gone. Probably.",
    "{name} wants to party. Not literally. Someone invite them anyway.",
    "Hi {name}! Fresh ink, fresh quests, same old guild.",
    "{name}'s back. Lock your doors and ready the dad jokes.",
    "Welcome home, {name}.",
    "Well, well, well. If it isn't {name}.",
    "{name} returns! Cue dramatic music.",
    "{name}, you're online. Your mailbox called. It's worried about you.",
    "Back already, {name}? The real world can't have been that bad.",
    "Hey {name}, the murlocs send their regards. Mrglglgl.",
    "Welcome back, {name}. The floor is not lava. The lava is lava.",
    "{name} logged in. Morale up 4 percent. Loot down 4 percent.",
    "Hello {name}! Today's forecast: questing, with a chance of wipes.",
    "Ah, {name}. The legend. The myth. The one who still owes someone a flask.",
    "{name} is online. Someone tell the flight master to warm up the gryphons.",
    "Welcome back, {name}. Your quest log missed you. It told me.",
    "Hi {name}. Stay hydrated. Mages, that's your cue.",
    "{name}! Looking very... pixelated today. In a good way.",
    "Look alive, everyone. {name} just logged in.",
    "Welcome back, {name}. Let's go make some bad decisions in a dungeon.",
    "{name} is here! Quick, someone pretend we were being productive.",
    "Greetings, {name}. Adventure awaits. Possibly also a boat.",
    "{name} has logged in. Nice work, that's the hard part done.",
    "Hey {name}. Fun fact: nobody has read the boss guide. Including you.",
    "Oi, {name}! Good to see you.",
    "Welcome back, {name}. The inn's warm, the ale's cheap, the guild's chaos.",
    "{name}'s online. That's my cue to sharpen myself.",
}

-- Said in guild chat when someone joins the guild.
QuillPhrases.newMember = "Everyone, welcome {name} to the guild! I'm Quill, the guild scribe."

-- Class greetings, by mood. Quill roasts the character and the class, never the person.
QuillPhrases.classGreetings = {
    PALADIN = {
        Mean      = "Ah. {name}, one of our most useless Paladins. Great to have you on.",
        Sarcastic = "Hey look everyone, it's the best Paladin on the server... {name} XD",
        Funny     = "Hello {name}, have you specced Holy yet to do max DPS :D",
    },
    WARRIOR = {
        Mean      = "Ah, {name}. Our warrior. Remember: charge first, think never.",
        Sarcastic = "Stand back everyone, {name} is here to pull for us. Again. XD",
        Funny     = "Hi {name}! Have you tried turning your rage off and on again? :D",
    },
    HUNTER = {
        Mean      = "{name} the hunter is on. Lock up the trash mobs, they'll get pulled anyway.",
        Sarcastic = "Oh good, {name}'s here. The pet was getting lonely XD",
        Funny     = "Hi {name}! Did you remember to feed the pet this time? :D",
    },
    ROGUE = {
        Mean      = "{name} is online. Count your gold.",
        Sarcastic = "Did anyone see {name} log in? No? Typical rogue XD",
        Funny     = "Welcome back {name}! Quick, everyone check your pockets :D",
    },
    PRIEST = {
        Mean      = "{name} the priest is here. Try healing someone other than yourself tonight.",
        Sarcastic = "Rejoice, {name} has arrived to watch us stand in fire XD",
        Funny     = "Hi {name}! Bandages are cheaper, but we'll keep you anyway :D",
    },
    SHAMAN = {
        Mean      = "{name} is on. Someone tell them which totem actually does something.",
        Sarcastic = "Ah {name}, master of the elements and 47 totems nobody asked for XD",
        Funny     = "Hello {name}! Drop a totem so we know where you've been :D",
    },
    MAGE = {
        Mean      = "{name} the mage. Useful for water, otherwise questionable.",
        Sarcastic = "Everyone, {name}'s here. Form an orderly queue for free food XD",
        Funny     = "Hi {name}! Port to Ironforge? That'll be one hug and a tip :D",
    },
    WARLOCK = {
        Mean      = "{name} has logged in. The imp's the brains of that operation.",
        Sarcastic = "Welcome back {name}, our resident ray of sunshine XD",
        Funny     = "Hi {name}! How many soul shards are we hoarding today? :D",
    },
    DRUID = {
        Mean      = "{name} the druid is on. Can't decide what to be, much like their spec.",
        Sarcastic = "Look, it's {name}! Or a bear. Or a cat. Who can tell? XD",
        Funny     = "Hi {name}! Which form today: bear, cat or tree? :D",
    },
}


-- ---- Level-up cheers ({level} = the level they reached) ------
QuillPhrases.levelUp = {
    "Ding! Congrats {name} on level {level}!",
    "{name} just hit level {level}. Someone get the confetti.",
    "Level {level}, {name}! Grats. Your trainer misses you.",
    "Look at {name}, level {level} already. Grats!",
    "Grats on {level}, {name}! Only a few more bars of purple to go.",
}
QuillPhrases.levelCap = {
    "DING 60! Huge congrats {name}. Welcome to the endgame - raid's that way.",
    "{name} just hit 60! Grats. Now the real grind begins.",
}

-- ---- New members: 5 questions by whisper (from the Day-One Pack) ----
QuillPhrases.newMemberIntro = "Hi {name}, I'm Quill. Mind answering 5 quick questions so the guild gets to know you? Say \"skip\" any time."
QuillPhrases.newMemberQuestions = {
    { field = "Main or alt",        ask = "Is this your main character, or an alt? If it's an alt, who's your main?" },
    { field = "Role",               ask = "What do you like to play: tank, healer or damage?" },
    { field = "Raiding",            ask = "Are you interested in raiding?" },
    { field = "Usual play time",    ask = "What time of day do you usually play?" },
    { field = "Found the guild via", ask = "How did you find the guild?" },
}
QuillPhrases.newMemberThanks = "Thanks {name}, all noted. Say \"hey quill, help\" in guild chat any time."
QuillPhrases.newMemberSkip   = "No worries, {name}. Welcome aboard!"

-- ---- Hush ----
QuillPhrases.hushed   = "Quill will be quiet for {minutes} minutes (hushed by {name})."
QuillPhrases.unhushed = "Quill is back (unhushed by {name})."


-- ---- When the guild has no back office (no officer PC running Quill's bridge) ----
-- Then nothing Quill writes down goes anywhere, so he doesn't promise to find out.
QuillPhrases.noOffice = {
    unknown = "Not sure, {name}. Best to ask an officer.",
    teach   = "Thanks {name}, but this guild hasn't set up my notebook, so I can't learn that. Tell an officer?",
    newJoke = "Ha! Sadly this guild hasn't set up my joke box, {name}. Tell it in guild chat instead.",
    help3   = "If I don't know something, ask an officer.",
}

QuillPhrases.about = "Quill v{version}, the guild scribe. Designed by narx00, coded by Claude (claude.ai), Anthropic's AI."
