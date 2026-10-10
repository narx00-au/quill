-- ============================================================
--  Quill - in-game addon  (the brain)
--
--  What Quill says lives in QuillPhrases.lua.
--  Your guild's answers and settings live in QuillGuild.lua.
--  Talking to other copies of Quill lives in QuillComms.lua.
--  This file decides WHEN to say what.
--
--  Lines starting with -- are notes for humans. WoW skips them.
-- ============================================================

local PURPLE = "|cffc8a2c8"   -- colour code for Quill's name in your own chat window
local PLAIN  = "|r"
local GAP    = 1.5            -- seconds between Quill's messages, so the game never mutes him
local PREFIX = "Quill: "      -- every line Quill sends starts with this

local function note(text)     -- a message only YOU see, in your chat window
    print(PURPLE .. "Quill:" .. PLAIN .. " " .. text)
end


-- ---- Small helpers -------------------------------------------

-- Swap {name} (and friends) for the real thing.
local function fill(line, name, extra)
    line = line:gsub("{name}", function() return name end)
    line = line:gsub("{where}", function()              -- " and post it in #quill on Discord", or nothing
        local channel = QuillGuild and QuillGuild.answersChannel or ""
        return channel ~= "" and (" and post it in " .. channel .. " on Discord") or ""
    end)
    if extra then
        for key, value in pairs(extra) do
            line = line:gsub("{" .. key .. "}", function() return tostring(value) end)
        end
    end
    return line
end

-- Tidy a message so "Hey, Quill!!  You're USELESS" becomes "hey quill youre useless".
local function tidy(text)
    text = text:lower():gsub("'", "")      -- you're -> youre
    text = text:gsub("[%p]", " ")          -- other punctuation -> spaces
    text = text:gsub("%s+", " ")           -- squash runs of spaces
    return (text:gsub("^ ", ""):gsub(" $", ""))
end

-- Does the tidied text contain this word or phrase as whole words?
local function has(text, phrase)
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function hasAny(text, phrases)
    for _, phrase in ipairs(phrases) do
        if has(text, phrase) then return true end
    end
    return false
end

-- Pick a random line, never the same as last time from the same list.
local lastPick = {}
local function pick(list)
    if #list == 1 then return list[1] end
    local choice
    repeat choice = math.random(#list) until choice ~= lastPick[list]
    lastPick[list] = choice
    return list[choice]
end

-- Like shuffling a deck: hand out every line once, in random order, before any repeats.
local decks = {}
local function shuffled(list)
    local deck = decks[list]
    if not deck or #deck == 0 then
        deck = {}
        for i = 1, #list do deck[i] = i end
        for i = #deck, 2, -1 do
            local j = math.random(i)
            deck[i], deck[j] = deck[j], deck[i]
        end
        decks[list] = deck
    end
    return list[table.remove(deck)]
end

local function ordinal(n)
    local last2 = n % 100
    if last2 >= 11 and last2 <= 13 then return n .. "th" end
    local last = n % 10
    if last == 1 then return n .. "st" elseif last == 2 then return n .. "nd"
    elseif last == 3 then return n .. "rd" end
    return n .. "th"
end

-- The text the player typed after a keyword, with their own capitals kept.
-- e.g. "Hey Quill, teach Mages can make water" -> "Mages can make water"
local function textAfter(message, keyword)
    local _, finish = message:lower():find(keyword, 1, true)
    if not finish then return "" end
    local rest = message:sub(finish + 1):gsub("^[%s%p]+", ""):gsub("%s+$", "")
    return rest
end

local function isSecret(value)   -- Forever hides some text from addons in combat; leave those alone
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Settings come from QuillGuild.lua; /quill commands can override them on this PC.
local function setting(key)
    if QuillDB and QuillDB.settings and QuillDB.settings[key] ~= nil then return QuillDB.settings[key] end
    return QuillGuild and QuillGuild[key]
end

local function inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function gameMajorMinor(version)    -- "1.60.1" -> "1.60"
    return (tostring(version or ""):match("^(%d+%.%d+)")) or ""
end


-- ---- Being polite: hush, raid quiet ---------------------------

local function isHushed()
    return time() < (QuillDB.hushUntil or 0)
end

-- Quiet in guild chat: hushed by an officer, or the speaker is inside a raid.
local function guildQuiet()
    return isHushed() or (setting("quietInRaid") and QuillComms.isBusy())
end


-- Guild chat allows 255 characters. Long answers get split at a space.
local LIMIT = 255 - #PREFIX - 5
local function chunks(line)
    local pieces = {}
    while #line > LIMIT do
        local cut = line:sub(1, LIMIT):match("^.*() ") or LIMIT
        table.insert(pieces, (line:sub(1, cut - 1):gsub("%s+$", "")))
        line = line:sub(cut + 1)
    end
    table.insert(pieces, line)
    return pieces
end


-- ---- What officers have approved (QuillLearned.lua) ---------
-- The bridge writes QuillLearned.lua from what officers approved in Discord.
-- WoW only reads it at login or /reload; other copies get it over the hidden channel.

local SKIP = {}
for word in ("a an the is are was were what whats who how do does did can could i you me my to of in on for at it "
          .. "its and or be with hey quill please tell about which where when why there this that should would "
          .. "any get got"):gmatch("%S+") do
    SKIP[word] = true
end

local function keywords(text)
    local found, count = {}, 0
    for word in tidy(text):gmatch("%S+") do
        if not SKIP[word] and not found[word] then found[word] = true; count = count + 1 end
    end
    return found, count
end

local function overlap(a, b)
    local shared = 0
    for word in pairs(a) do if b[word] then shared = shared + 1 end end
    return shared
end

-- "[Patch 1.60, 10 Oct] answer" - and "may be outdated" once the game has moved on (Day-One Pack format).
local function withPatchTag(item)
    if not item.patch or item.patch == "" then return item.a end
    local stamp = "Patch " .. gameMajorMinor(item.patch)
    if item.when and item.when > 0 and date then stamp = stamp .. ", " .. date("%d %b", item.when) end
    if gameMajorMinor(item.patch) ~= gameMajorMinor((GetBuildInfo())) then
        stamp = stamp .. ", may be outdated"
    end
    return "[" .. stamp .. "] " .. item.a
end

-- Find the approved answer or fact that best fits what was asked.
local function lookupLearned(asked)
    local L = QuillComms.learned()
    if not L then return nil end
    local want, wantCount = keywords(asked)
    if wantCount == 0 then return nil end
    local best, bestScore = nil, 0

    for _, item in ipairs(L.answers or {}) do
        local words, count = keywords(item.q)
        local shared = overlap(want, words)
        local score = shared / math.max(wantCount, count)
        if shared > 0 and score >= 0.6 and score > bestScore then
            best, bestScore = withPatchTag(item), score
        end
    end
    for _, item in ipairs(L.facts or {}) do
        local words, count = keywords(item.text)
        local shared = overlap(want, words)
        local score = count > 0 and shared / count or 0
        if (shared >= 2 or count == 1) and score >= 0.6 and score > bestScore then
            local fact = item.text:gsub("^%l", string.upper)
            if not fact:find("[%.!?]$") then fact = fact .. "." end
            best, bestScore = fact .. " Taught by " .. item.author .. ".", score
        end
    end
    return best
end


-- ---- The queue: one message every GAP seconds ---------------

local queue   = {}        -- lines waiting to be said, first in first out: { owner, line, to }
local sending = false

local function peopleAhead()
    local seen, count = {}, 0
    for _, item in ipairs(queue) do
        if not seen[item.owner] then seen[item.owner] = true; count = count + 1 end
    end
    return count
end

local function pump()
    if sending or #queue == 0 then return end
    sending = true
    if setting("holdInCombat") and inCombat() then          -- wait the fight out, then carry on
        C_Timer.After(2, function() sending = false; pump() end)
        return
    end
    local item = table.remove(queue, 1)
    if item.to then
        SendChatMessage(PREFIX .. item.line, "WHISPER", nil, item.to)
    elseif IsInGuild() then
        SendChatMessage(PREFIX .. item.line, "GUILD")
    else
        note("(not in a guild, would have said) " .. item.line)
    end
    C_Timer.After(GAP, function()
        sending = false
        pump()
    end)
end

-- Queue up one or more lines for a player. whisperTo = answer privately instead of in guild chat.
local function reply(name, lines, fullName, whisperTo, extra)
    if type(lines) == "string" then lines = { lines } end

    -- If they'd be waiting more than ~10 seconds, whisper them their place in line.
    local waitSeconds = #queue * GAP
    if waitSeconds > 10 and fullName and not whisperTo and IsInGuild() then
        local place = ordinal(peopleAhead() + 1)
        SendChatMessage(PREFIX .. fill(QuillPhrases.standard.busy, name, { place = place }),
            "WHISPER", nil, fullName)
    end

    for _, line in ipairs(lines) do
        for _, piece in ipairs(chunks(fill(line, name, extra))) do
            table.insert(queue, { owner = name, line = piece, to = whisperTo })
        end
    end
    pump()
end


-- ---- Spam guard: a few requests per person per minute -------

local recent = {}        -- name -> times of their recent requests
local warned = {}        -- name -> when we last said "give me a minute"

-- Returns true if this person may have an answer now.
local function allowed(name, respondWarn)
    local limit, period = setting("rateLimit") or 3, setting("ratePeriod") or 60
    local times, now, kept = recent[name] or {}, time(), {}
    for _, t in ipairs(times) do
        if now - t < period then table.insert(kept, t) end
    end
    if #kept >= limit then
        recent[name] = kept
        if now - (warned[name] or 0) >= period then
            warned[name] = now
            respondWarn(QuillPhrases.standard.slowDown)
        end
        return false
    end
    table.insert(kept, now)
    recent[name] = kept
    return true
end


-- ---- Does this guild have a back office? -------------------
-- True if this PC runs the bridge, or a copy has ever met one that does.
-- Without one, nothing Quill writes down goes anywhere, so he words things differently.
local function hasBackOffice()
    return QuillComms.isBridgePC() or (QuillDB and QuillDB.officeSeen ~= nil)
end

-- The line to say, or the no-back-office version of it.
local function officeLine(key)
    if not hasBackOffice() and QuillPhrases.noOffice and QuillPhrases.noOffice[key] then
        return QuillPhrases.noOffice[key]
    end
    return QuillPhrases.standard[key]
end

local function helpLines()
    local lines = {}
    for i, line in ipairs(QuillPhrases.help) do lines[i] = line end
    if not hasBackOffice() and QuillPhrases.noOffice and QuillPhrases.noOffice.help3 then
        lines[3] = QuillPhrases.noOffice.help3
    end
    return lines
end


-- ---- Things Quill writes down for the officers --------------
-- Saved in WTF\...\SavedVariables\Quill.lua when you log out or /reload.
-- The bridge sends them on to #quill-review (questions, lessons, jokes) or #new-members.

local function record(kind, name, text)
    local entry = { kind = kind, name = name, text = text, when = time(), patch = (GetBuildInfo()) }
    table.insert(QuillDB.inbox, entry)
    QuillComms.shareNote(entry)          -- make sure it reaches the officers' PC (QuillComms.lua)
end


-- ---- Working out what someone wants -------------------------

-- ---- Guessing what someone means ----------------------------
-- QuillPhrases.intents lists the ways people say "teach", "joke" and so on.
-- If they say WHAT but not the thing itself ("I want you to learn something"), Quill asks,
-- and their next message (no "quill" needed) is taken as the answer.

local DEFAULT_INTENTS = {
    newJoke = { "new joke" }, teach = { "teach" }, help = { "help" }, joke = { "joke" },
}
local FILLER = { [""] = true, ["something"] = true, ["something new"] = true, ["a thing"] = true,
                 ["this"] = true, ["stuff"] = true, ["one"] = true, ["a joke"] = true, ["something for you"] = true,
                 ["a new joke"] = true, ["you something"] = true, ["something from me"] = true,
                 ["for you"] = true, ["for ya"] = true, ["you"] = true, ["something you should know"] = true }

local function looksLikeQuestion(message, rest)
    return message:find("?", 1, true) or rest:find("^what") or rest:find("^where") or rest:find("^how")
        or rest:find("^when") or rest:find("^who") or rest:find("^why") or rest:find("^which")
        or rest:find("^can ") or rest:find("^does ") or rest:find("^do ") or rest:find("^is ")
        or rest:find("^are ") or rest:find("^did ") or false
end

-- Returns the intent ("newJoke", "teach", "help", "joke" or nil) and what came after the trigger words.
local function guessIntent(rest, message)
    local intents = QuillPhrases.intents or DEFAULT_INTENTS
    local question = looksLikeQuestion(message, rest)
    for _, kind in ipairs({ "newJoke", "teach", "help", "joke" }) do
        local phrases = {}
        for _, phrase in ipairs(intents[kind] or {}) do table.insert(phrases, phrase) end
        table.sort(phrases, function(a, b) return #a > #b end)      -- "joke for you" before "joke"
        for _, phrase in ipairs(phrases) do
            local hit = has(rest, phrase)
            if kind == "help" then hit = rest == phrase or rest:find("^" .. phrase) ~= nil end
            if hit and kind == "teach" and question and phrase ~= "teach" and phrase ~= "did you know" then
                hit = false                     -- "do you remember when raid is?" is a question, not a lesson
            end
            if hit then
                local content = textAfter(message, phrase)
                content = content:gsub("^[Tt]hat%s+", ""):gsub("^[Aa]bout%s+", ""):gsub("^[Tt]his:?%s*", "")
                if FILLER[tidy(content)] then content = "" end
                return kind, content
            end
        end
    end
end

local waitingFor = {}    -- name -> { kind = "teach"/"newJoke", untilTime } : Quill asked them a follow-up

-- Used if the phrasebook has no wakeWords list (an older bridge PC's copy).
DEFAULT_WAKES = { { words = "hey quill", firm = true }, { words = "quill" } }

-- whisperTo: set when someone whispered this copy - answer them privately.
local function handle(message, sender, whisperTo)
    if isSecret(message) or isSecret(sender) then return end
    -- Never answer ourselves (or anyone pretending to be Quill).
    if message:sub(1, #PREFIX) == PREFIX then return end

    local name  = Ambiguate(sender, "short")   -- "Grimtusk-Realm" becomes "Grimtusk"
    local text  = tidy(message)
    local P     = QuillPhrases
    local function respond(lines) return reply(name, lines, sender, whisperTo) end

    -- Did Quill just ask them "what should I learn?" - then this message is the answer.
    local waiting = waitingFor[name]
    if waiting then
        waitingFor[name] = nil
        local startsWithWake = false
        for _, wake in ipairs(P.wakeWords or DEFAULT_WAKES) do
            if text == wake.words or text:sub(1, #wake.words + 1) == wake.words .. " " then startsWithWake = true end
        end
        if time() <= waiting.untilTime and not startsWithWake then
            if not message:find("%a") or hasAny(text, { "never mind", "nevermind", "nvm", "cancel", "forget it" }) then
                return respond(P.standard.cancelled or "No worries, {name}.")
            end
            local content = message:gsub("^%s+", ""):gsub("%s+$", "")
            if waiting.kind == "newJoke" then
                record("joke", name, content)
                return respond(officeLine("newJoke"))
            else
                record("teach", name, content)
                return respond(officeLine("teach"))
            end
        end
    end

    -- Was Quill spoken TO ("hey quill ...") or just mentioned ("thanks quill", "quill you're useless")?
    local rest, spokenTo, asked
    local loosely = false                -- "yo quill joke": only real-looking questions go to the officers

    -- Wake words: the ways to get Quill's attention, longest first ("hey quill" before "quill").
    -- The list lives in QuillPhrases.wakeWords, so it travels to every copy with the guild's words.
    local wakes = P.wakeWords or DEFAULT_WAKES
    table.sort(wakes, function(a, b) return #a.words > #b.words end)
    for _, wake in ipairs(wakes) do
        local w = wake.words
        if text == w or text:sub(1, #w + 1) == w .. " " then
            rest, spokenTo, loosely = text:sub(#w + 2), true, not wake.firm
            asked = textAfter(message, w:match("(%S+)$"))        -- their words after the wake, capitals kept
            break
        end
    end

    if not spokenTo then
        if message:find("?", 1, true) and text:find(" quill$") then
            -- "what time is raid, quill?" - asking him, with his name at the end
            rest, spokenTo, loosely = text:sub(1, -7), true, true
            asked = message:gsub("[%s,]*[Qq][Uu][Ii][Ll][Ll]%s*%?*%s*$", "") .. "?"
        elseif has(text, "quill") and not whisperTo then
            rest, spokenTo = (" " .. text .. " "):gsub(" quill ", " "), false
            rest = tidy(rest)
        else
            return   -- nothing to do with Quill
        end
    end

    -- Spam guard: past the limit, one "give me a minute" and then silence.
    if not allowed(name, respond) then return end

    if spokenTo then
        if rest == "" then
            return respond(pick(P.smallTalk[1].lines))          -- just "hey quill"
        end

        local intent, content = guessIntent(rest, message)

        if intent == "help" then
            return respond(helpLines())
        end

        if intent == "newJoke" then
            if not hasBackOffice() then return respond(officeLine("newJoke")) end   -- nowhere to send it
            if content == "" then
                waitingFor[name] = { kind = "newJoke", untilTime = time() + 90 }
                return respond(P.standard.askJoke or P.standard.emptyJoke)
            end
            record("joke", name, content)
            return respond(officeLine("newJoke"))
        end

        if intent == "teach" then
            if not hasBackOffice() then return respond(officeLine("teach")) end   -- nowhere to send it
            if content == "" then
                waitingFor[name] = { kind = "teach", untilTime = time() + 90 }
                return respond(P.standard.askLesson or P.standard.emptyTeach)
            end
            record("teach", name, content)
            return respond(officeLine("teach"))
        end

        if intent == "joke" then
            local learned = QuillComms.learned().jokes or {}
            if #learned > 0 and math.random(#P.jokes + #learned) > #P.jokes then
                local joke = learned[math.random(#learned)]
                return respond("Joke by " .. joke.author .. ": " .. joke.text)
            end
            return respond(pick(P.jokes))
        end

        if has(rest, "be nice to me") then
            QuillDB.nice[name] = true
            return respond(P.standard.beNice)
        end

        if has(rest, "roast me") then
            QuillDB.nice[name] = nil
            return respond(P.standard.roastMe)
        end

        -- Something the officers approved beats the generic guild questions ("bank in stormwind" isn't the guild bank).
        local learnedFirst = lookupLearned(rest)
        if learnedFirst then return respond(learnedFirst) end

        for _, question in ipairs(P.guildQuestions) do
            if hasAny(rest, question.words) then
                local answer = QuillGuild and QuillGuild[question.key] or ""
                if answer == "" then answer = P.standard.askOfficer end
                return respond(answer)
            end
        end
    end

    -- Small talk works both ways: "hey quill, thanks" and "thanks quill".
    for _, topic in ipairs(P.smallTalk) do
        if hasAny(rest, topic.words) then
            return respond(pick(topic.lines))
        end
    end

    -- Something the officers have approved?
    if spokenTo then
        local learned = lookupLearned(rest)
        if learned then return respond(learned) end
    end

    -- a loose wake ("quill is cool", "yo quill nice") that isn't a question - don't bother the officers with it.
    if loosely and not (message:find("?", 1, true) or rest:find("^what") or rest:find("^where")
            or rest:find("^how") or rest:find("^when") or rest:find("^who") or rest:find("^why")
            or rest:find("^which") or rest:find("^can ") or rest:find("^does ") or rest:find("^do ")) then
        return
    end

    -- Spoken to, but no idea what they mean: write it down for the officers.
    if spokenTo then
        record("question", name, asked or textAfter(message, "quill"))
        return respond(officeLine("unknown"))
    end
end


-- ---- The guild roster: classes and levels -------------------

local classOf = {}                       -- "Grimtusk" -> "WARRIOR"
local levelOf = {}                       -- "Grimtusk" -> 37
local rosterSeen = false                 -- first look is just a baseline - no cheering for old levels
local cheerLevel                         -- defined below (needs reply)

local function readRoster()
    for i = 1, GetNumGuildMembers() do
        local fullName, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if fullName then
            local who = Ambiguate(fullName, "short")
            if classFile then classOf[who] = classFile end
            if level then
                local before = levelOf[who]
                levelOf[who] = level
                if rosterSeen and online and before and level > before then
                    cheerLevel(who, level)
                end
            end
        end
    end
    rosterSeen = true
end


-- ---- Greeting guildies who log in ---------------------------

local DAYS = { Sun = 1, Mon = 2, Tue = 3, Wed = 4, Thu = 5, Fri = 6, Sat = 7 }

local function minutesOf(clock)           -- "20:30" -> 1230
    local h, m = clock:match("(%d+):(%d+)")
    return tonumber(h) * 60 + tonumber(m)
end

local function serverNow()                -- the realm's calendar: weekday (1 = Sunday), hour, minute, day, month, year
    return C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
end

local function isRaidTime()
    local now = serverNow()
    if not now then return false end
    local minute = now.hour * 60 + now.minute
    for _, slot in ipairs(setting("raidHours") or {}) do
        if DAYS[slot.day] == now.weekday and minute >= minutesOf(slot.from) and minute < minutesOf(slot.to) then
            return true
        end
    end
    return false
end

-- Pick the greeting line for this person, following the mood and their "be nice" choice.
local function greetingFor(name, mood)
    local P = QuillPhrases
    local forced = mood ~= nil          -- /quill preview asks for a specific mood
    mood = mood or setting("mood") or "Funny"
    if QuillDB.nice[name] then
        mood = "Funny"
    elseif mood == "Random" then
        local moods = { "Plain", "Funny", "Sarcastic" }
        if setting("allowMean") then table.insert(moods, "Mean") end
        mood = moods[math.random(#moods)]
    elseif mood == "Mean" and not setting("allowMean") then
        mood = "Sarcastic"
    end
    local lines = P.classGreetings[classOf[name] or ""]
    if mood == "Plain" or not lines or not lines[mood] or (not forced and math.random(3) > 1) then
        return shuffled(P.greetings)
    end
    return lines[mood]
end

local function greet(name)
    if not QuillComms.isSpeaker() or not setting("greetings") or guildQuiet() then return end
    if name == UnitName("player") then return end
    local gapSeconds = (setting("greetGap") or 8) * 3600
    if time() - (QuillDB.greeted[name] or 0) < gapSeconds then return end
    if isRaidTime() then return end
    QuillDB.greeted[name] = time()            -- greeted OR skipped: either way, no new roll for greetGap hours
    if math.random(100) > (setting("greetChance") or 100) then return end   -- not everyone, every time
    C_Timer.After(3, function() reply(name, greetingFor(name)) end)   -- a short pause feels less robotic
end


-- ---- Level-up cheers ----------------------------------------

function cheerLevel(name, level)
    if not setting("levelCheers") or not QuillComms.isSpeaker() or guildQuiet() then return end
    local milestone = false
    for _, m in ipairs(setting("levelMilestones") or {}) do
        if m == level then milestone = true end
    end
    if not milestone then return end
    QuillDB.cheered = QuillDB.cheered or {}
    if QuillDB.cheered[name .. ":" .. level] then return end
    QuillDB.cheered[name .. ":" .. level] = time()
    local maxMilestone = 0
    for _, m in ipairs(setting("levelMilestones") or {}) do maxMilestone = math.max(maxMilestone, m) end
    local lines = (level == maxMilestone and QuillPhrases.levelCap) or QuillPhrases.levelUp
    C_Timer.After(2, function() reply(name, pick(lines), nil, nil, { level = level }) end)
end


-- ---- New members: welcome, then 5 questions by whisper ------

local interviews = {}     -- name -> { step, answers, started, whisperTo }

local function finishInterview(name, skipped)
    local talk = interviews[name]
    if not talk then return end
    interviews[name] = nil
    local parts = {}
    for i, q in ipairs(QuillPhrases.newMemberQuestions) do
        if talk.answers[i] then table.insert(parts, q.field .. ": " .. talk.answers[i]) end
    end
    if #parts > 0 then
        record("newmember", name, table.concat(parts, " | "))
    end
    if skipped then
        reply(name, QuillPhrases.newMemberSkip, nil, talk.whisperTo)
    elseif talk.step > #QuillPhrases.newMemberQuestions then
        reply(name, QuillPhrases.newMemberThanks, nil, talk.whisperTo)
    end
end

local function askNext(name)
    local talk = interviews[name]
    local q = QuillPhrases.newMemberQuestions[talk.step]
    if q then
        reply(name, talk.step .. "/" .. #QuillPhrases.newMemberQuestions .. ": " .. q.ask, nil, talk.whisperTo)
    else
        finishInterview(name, false)
    end
end

local function interviewAnswer(name, message)
    local talk = interviews[name]
    if tidy(message) == "skip" then return finishInterview(name, true) end
    talk.answers[talk.step] = message:gsub("|", "/")
    talk.step = talk.step + 1
    askNext(name)
end

local function welcomeNewMember(name, fullName)
    if not QuillComms.isSpeaker() then return end
    QuillDB.greeted[name] = time()                     -- no "welcome back" straight after joining
    if not guildQuiet() then
        C_Timer.After(3, function() reply(name, QuillPhrases.newMember) end)
    end
    if setting("newMemberQuestions") and QuillPhrases.newMemberQuestions then
        C_Timer.After(10, function()
            interviews[name] = { step = 1, answers = {}, started = time(), whisperTo = fullName or name }
            reply(name, QuillPhrases.newMemberIntro, nil, fullName or name)
            askNext(name)
        end)
    end
end

-- Questions not answered within 10 minutes: stop asking, keep what we have.
local function checkInterviews()
    for name, talk in pairs(interviews) do
        if time() - talk.started > 600 then
            finishInterview(name, false)
        end
    end
end


-- ---- Scheduled announcements (set by officers in Discord: !announce) ----

local function announcementKey(item, now)
    return item.id .. ":" .. now.year .. "-" .. now.month .. "-" .. now.monthDay
end

local function checkAnnouncements()
    if not QuillComms.isSpeaker() or isHushed() then return end
    local now = serverNow()
    if not now then return end
    local minute = now.hour * 60 + now.minute
    QuillDB.fired = QuillDB.fired or {}
    for _, item in ipairs(QuillComms.learned().announcements or {}) do
        local key = announcementKey(item, now)
        local due = DAYS[item.day] == now.weekday and minute >= minutesOf(item.time)
                    and minute < minutesOf(item.time) + 3        -- a 3-minute window, in case of a /reload
        local done = QuillDB.fired[key] or (not item.repeating and QuillDB.fired[item.id])
        if due and not done then
            QuillDB.fired[key] = time()
            if not item.repeating then QuillDB.fired[item.id] = time() end
            QuillComms.shareFired(key, item.repeating and nil or item.id)
            reply("Quill", item.text)
        end
    end
end


-- ---- Listening to the game ----------------------------------

-- "|Hplayer:Grimtusk|h[Grimtusk]|h has come online."  ->  "Grimtusk has come online."
local function plainSystemText(message)
    return (message:gsub("|Hplayer:[^|]*|h%[?([^%]|]*)%]?|h", "%1"))
end

local function handleSystem(message)
    if isSecret(message) then return end
    local text = plainSystemText(message)
    local online = text:match("^(.-) has come online")
    if online then
        online = Ambiguate(online, "short")
        if classOf[online] then greet(online) end       -- guild members only, not friends
        return
    end
    local joined = text:match("^(.-) has joined the guild")
    if joined then
        welcomeNewMember(Ambiguate(joined, "short"), joined)
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
end

local function handleWhisper(message, sender)
    if isSecret(message) or isSecret(sender) then return end
    if message:sub(1, #PREFIX) == PREFIX then return end         -- another copy of Quill talking
    local name = Ambiguate(sender, "short")
    if interviews[name] then return interviewAnswer(name, message) end
    if not classOf[name] then return end                          -- guildies only
    handle(message, sender, sender)                               -- any copy answers whispers, privately
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("ADDON_LOADED")         -- our saved settings are ready
listener:RegisterEvent("PLAYER_LOGIN")         -- you've finished loading in
listener:RegisterEvent("CHAT_MSG_GUILD")       -- someone said something in guild chat
listener:RegisterEvent("CHAT_MSG_WHISPER")     -- someone whispered you
listener:RegisterEvent("CHAT_MSG_SYSTEM")      -- "X has come online", "X has joined the guild"
listener:RegisterEvent("GUILD_ROSTER_UPDATE")  -- the guild list (names, classes, levels) changed

listener:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "Quill" then
        QuillDB = QuillDB or {}
        QuillDB.inbox   = QuillDB.inbox or {}
        QuillDB.nice    = QuillDB.nice or {}
        if QuillDB.speaker == nil then QuillDB.speaker = true end
        QuillDB.greeted  = QuillDB.greeted or {}
        QuillDB.settings = QuillDB.settings or {}

    elseif event == "PLAYER_LOGIN" then
        local version, _, _, interface = GetBuildInfo()
        note("v" .. QuillComms.addonVersion() .. " loaded (game " .. version .. ", interface " .. interface .. "). Type /quill for options.")
        local L = QuillComms.learned()
        note("Knows " .. #(L.answers or {}) .. " answer(s), " .. #(L.facts or {}) .. " fact(s), "
             .. #(L.jokes or {}) .. " guild joke(s) and " .. #(L.announcements or {}) .. " announcement(s) from the officers.")
        if not QuillDB.speaker then note("Speaker is OFF - I'm listening but not talking.") end
        if isHushed() then note("Quill is hushed for another " .. math.ceil((QuillDB.hushUntil - time()) / 60) .. " minute(s).") end
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end   -- ask for the guild list
        C_Timer.NewTicker(30, function()
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end   -- keeps levels fresh
            checkAnnouncements()
            checkInterviews()
        end)

    elseif event == "GUILD_ROSTER_UPDATE" then
        readRoster()

    elseif event == "CHAT_MSG_SYSTEM" then
        handleSystem(arg1)

    elseif event == "CHAT_MSG_WHISPER" then
        handleWhisper(arg1, arg2)

    elseif event == "CHAT_MSG_GUILD" then
        if QuillComms.isSpeaker() and not guildQuiet() then handle(arg1, arg2) end
    end
end)


-- ---- Making Quill's lines look like Quill's -----------------
-- On YOUR screen (and every guildie with the addon), "narx00: Quill: hi"
-- is redrawn as "[Quill]: hi". People without the addon still see the speaker's name.

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(frame, event, message, sender, ...)
        if issecretvalue and issecretvalue(message) then return false end
        if message:sub(1, #PREFIX) == PREFIX then
            return false, message:sub(#PREFIX + 1), "Quill", ...
        end
    end)
end


-- ---- The /quill command -------------------------------------

SLASH_QUILL1 = "/quill"
SlashCmdList.QUILL = function(input)
    local command = tidy(input or "")

    if command == "test" then
        reply(UnitName("player"), "hello. This is a test.")

    elseif command == "speaker" then
        QuillDB.speaker = not QuillDB.speaker
        note("Speaking is now " .. (QuillDB.speaker and "ALLOWED - this copy can be Quill's speaker." or "OFF - this copy will never speak."))
        QuillComms.announce()

    elseif command == "who" then
        QuillComms.describe()

    elseif command == "about" then
        note(fill(QuillPhrases.about or "Quill", UnitName("player"), { version = QuillComms.addonVersion() }))

    elseif command:find("^hush") then
        if not QuillComms.isOfficer() then return note("Only officers can hush Quill.") end
        local minutes = tonumber(command:match("^hush (%d+)")) or 30
        QuillComms.hush(time() + minutes * 60, minutes)

    elseif command == "unhush" then
        if not QuillComms.isOfficer() then return note("Only officers can unhush Quill.") end
        QuillComms.hush(0, 0)

    elseif command == "inbox" then
        local inbox = QuillDB.inbox
        note(#inbox .. " thing(s) written down for the officers.")
        for i = math.max(1, #inbox - 4), #inbox do
            local item = inbox[i]
            note("  " .. item.kind .. " from " .. item.name .. ": " .. item.text)
        end

    elseif command:find("^mood") then
        local wanted = command:match("^mood (%a+)")
        local moods = { plain = "Plain", funny = "Funny", sarcastic = "Sarcastic", mean = "Mean", random = "Random" }
        if wanted and moods[wanted] then
            QuillDB.settings.mood = moods[wanted]
            note("Mood is now " .. moods[wanted] .. ".")
            if moods[wanted] == "Mean" and not setting("allowMean") then
                note("(Mean lines are switched off in QuillGuild.lua - Quill will use Sarcastic instead.)")
            end
        else
            note("Mood is " .. (setting("mood") or "Funny") .. ". Try: /quill mood plain | funny | sarcastic | mean | random")
        end

    elseif command:find("^chance") then
        local wanted = tonumber(command:match("^chance (%d+)"))
        if wanted and wanted >= 0 and wanted <= 100 then
            QuillDB.settings.greetChance = wanted
            note("Quill now greets about " .. wanted .. "% of guildies who log in.")
        else
            note("Greeting chance is " .. (setting("greetChance") or 100) .. "%. Try: /quill chance 60")
        end

    elseif command == "greetings" then
        QuillDB.settings.greetings = not setting("greetings")
        note("Login greetings are now " .. (setting("greetings") and "ON." or "OFF."))

    elseif command == "preview" then
        local me = UnitName("player")
        local _, myClass = UnitClass("player")
        classOf[me] = classOf[me] or myClass
        note("How Quill would greet you (" .. (classOf[me] or "?") .. "), in each mood:")
        for _, mood in ipairs({ "Plain", "Funny", "Sarcastic", "Mean" }) do
            local saved = QuillDB.settings.allowMean
            QuillDB.settings.allowMean = true
            note("  " .. mood .. ": " .. fill(greetingFor(me, mood), me))
            QuillDB.settings.allowMean = saved
        end
        if isRaidTime() then note("(It's raid time right now, so real greetings are paused.)") end

    elseif command == "announcements" then
        local list = QuillComms.learned().announcements or {}
        note(#list .. " scheduled announcement(s) (server time):")
        for _, item in ipairs(list) do
            note("  " .. (item.repeating and "every " or "next ") .. item.day .. " " .. item.time .. ": " .. item.text)
        end

    else
        note("/quill about - who made Quill")
        note("/quill test - say a test line in guild chat")
        note("/quill who - which copies of Quill are online, and which one is speaking")
        note("/quill speaker - allow or stop this copy being Quill's speaker (now " .. (QuillDB.speaker and "allowed" or "off") .. ")")
        note("/quill hush [minutes] - officers: make Quill quiet in guild chat (default 30)  |  /quill unhush")
        note("/quill inbox - show what Quill has written down for the officers")
        note("/quill announcements - show what Quill is scheduled to announce")
        note("/quill preview - see how Quill would greet you, in every mood (only you see it)")
        note("/quill mood <plain|funny|sarcastic|mean|random> - now " .. (setting("mood") or "Funny"))
        note("/quill chance <0-100> - percent of logins Quill greets (now " .. (setting("greetChance") or 100) .. "%)")
        note("/quill greetings - turn login greetings on or off (now " .. (setting("greetings") and "ON" or "OFF") .. ")")
    end
end
