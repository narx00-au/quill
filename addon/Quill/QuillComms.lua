-- ============================================================
--  Quill - comms  (copies of Quill talking to each other)
--
--  Every guildie with Quill installed runs a copy. The copies talk
--  over WoW's hidden addon channel (guild-wide, players never see it)
--  so that:
--    1. Only ONE copy speaks in guild chat - the "speaker".
--       Preference: the PC running the bridge, then an officer, then
--       whoever has been online longest. If the speaker logs off,
--       the next one takes over.
--    2. Notes (questions, lessons, jokes) reach the bridge PC, even
--       when someone else's copy was the one that wrote them down.
--    3. Answers officers approved get shared to every copy, so any
--       speaker can use them.
--
--  Lines starting with -- are notes for humans. WoW skips them.
-- ============================================================

QuillComms = {}
local C = QuillComms

local PREFIX     = "QuillScribe" -- the hidden channel's name tag (unusual, so no other addon shares it)
local PROTOCOL   = 2         -- bump if the message format ever changes
local HEARTBEAT  = 60        -- seconds between "still here" messages (the speaker and front-runners)
local SLOW_BEAT  = 600       -- the longest any copy waits between them (big guilds, back of the queue)
local FRONT      = 3         -- this many front-runners answer a newcomer's "hello" and beat every minute
local TIMEOUT    = 150       -- seconds of silence before a front-runner counts as gone
local SEND_GAP   = 0.7       -- seconds between hidden messages (stay well under the game's limits)
local PIECE      = 200       -- characters per hidden message; longer ones are split and rejoined

local me                     -- this character's name
local peers = {}             -- other copies: name -> { since, bridge, officer, willing, learned, seen }
local lastSpeaker            -- so we can say when the speaker changes
local started = false

local function note(text)
    print("|cffc8a2c8Quill:|r " .. text)
end

local function short(name)
    return Ambiguate(name, "short")
end

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function clean(text)       -- tabs separate fields, so none allowed inside them
    return (tostring(text or ""):gsub("[\t\r\n]", " "))
end


-- ---- Facts about this copy -----------------------------------

-- The bridge stamps QuillLearned.lua with bridgePC, so a copy knows it's on the bridge PC.
function C.isBridgePC()
    return QuillLearned ~= nil and QuillLearned.bridgePC ~= nil
end

function C.isOfficer()
    local check = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote) or CanViewOfficerNote
    return check ~= nil and check() and true or false
end

-- What this copy knows: the bridge PC reads its file; everyone else uses what the bridge shared.
function C.learned()
    if C.isBridgePC() then return QuillLearned end
    if QuillDB and QuillDB.learned and (QuillDB.learned.version or 0) > ((QuillLearned or {}).version or 0) then
        return QuillDB.learned
    end
    return QuillLearned or {}
end

function C.learnedVersion()
    return (C.learned() or {}).version or 0
end


-- ---- Sending -------------------------------------------------

local outbox, urgent, sending, nextId = {}, {}, false, 0
local BULK = { CONTENT = true, LRN = true, LRNEND = true }   -- big transfers wait behind everything else

local function pump()
    if sending or (#outbox == 0 and #urgent == 0) then return end
    sending = true
    local message = table.remove(#urgent > 0 and urgent or outbox, 1)
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD")
    end
    C_Timer.After(SEND_GAP, function()
        sending = false
        pump()
    end)
end

-- send("NOTE", id, kind, ...) - any length; split into numbered pieces
local function send(...)
    local fields = { ... }
    for i = 1, select("#", ...) do fields[i] = clean(fields[i]) end
    local payload = table.concat(fields, "\t")
    nextId = (nextId % 999) + 1
    -- Cut into pieces, never through the middle of a letter like "é" (those take 2-4 bytes).
    local pieces, start = {}, 1
    while start <= #payload or #pieces == 0 do
        local finish = math.min(start + PIECE - 1, #payload)
        while finish < #payload and finish > start do
            local nextByte = payload:byte(finish + 1)
            if nextByte < 128 or nextByte >= 192 then break end   -- next byte starts a new letter
            finish = finish - 1
        end
        table.insert(pieces, payload:sub(start, finish))
        start = finish + 1
    end
    local queue = BULK[fields[1]] and outbox or urgent     -- "still here", notes, hush: straight to the front
    for i, piece in ipairs(pieces) do
        table.insert(queue, nextId .. ":" .. i .. "/" .. #pieces .. ":" .. piece)
    end
    pump()
end

local myBeat = HEARTBEAT       -- how often this copy says "still here" (it tells the others, so they know when to worry)

local function myStatus(kind)
    send(kind, PROTOCOL, QuillDB.loginAt or time(), C.isBridgePC() and 1 or 0, C.isOfficer() and 1 or 0,
         QuillDB.speaker and 1 or 0, C.learnedVersion(), C.addonVersion(), C.contentHash(), C.isBusy() and 1 or 0,
         myBeat)
end

-- A copy counts as gone after 2.5 of its own heartbeats of silence (never less than TIMEOUT).
local function alive(info)
    return time() - info.seen <= math.max(TIMEOUT, (info.beat or HEARTBEAT) * 2.5)
end


-- ---- Choosing the speaker ------------------------------------
-- Every copy runs the same rules on the same list, so they all pick the same speaker.

local function better(nameA, a, nameB, b)
    if (a.busy or false) ~= (b.busy or false) then return not a.busy end   -- someone not raiding beats someone raiding
    if a.bridge ~= b.bridge then return a.bridge end
    if a.officer ~= b.officer then return a.officer end
    if a.since ~= b.since then return a.since < b.since end
    return nameA < nameB
end

function C.speakerName()
    if not me then return nil end
    local bestName, best
    if QuillDB.speaker then
        bestName = me
        best = { bridge = C.isBridgePC(), officer = C.isOfficer(), since = QuillDB.loginAt or time(), busy = C.isBusy() }
    end
    for name, info in pairs(peers) do
        if info.willing and alive(info) then
            if not best or better(name, info, bestName, best) then
                bestName, best = name, info
            end
        end
    end
    return bestName
end

function C.isSpeaker()
    if not started then return false end      -- first ~10 seconds after login: listen before talking
    return C.speakerName() == me
end

-- My place in the queue: 1 = speaker, 2 = next in line... (counts only copies willing to speak)
function C.myPlace()
    if not me or not QuillDB.speaker then return 999 end
    local mine = { bridge = C.isBridgePC(), officer = C.isOfficer(), since = QuillDB.loginAt or time(), busy = C.isBusy() }
    local place = 1
    for name, info in pairs(peers) do
        if info.willing and alive(info) and better(name, info, me, mine) then place = place + 1 end
    end
    return place
end

-- Big guilds: hundreds of copies saying "still here" every minute would flood the hidden channel.
-- So only the front-runners (and the bridge PC) beat every minute; the rest slow down as the guild grows,
-- keeping the whole guild to roughly one "still here" every 3 seconds however many copies there are.
local function pickBeat()
    if C.isBridgePC() or C.myPlace() <= FRONT then return HEARTBEAT end
    local count = 0
    for _ in pairs(peers) do count = count + 1 end
    return math.min(SLOW_BEAT, math.max(HEARTBEAT, count * 3))
end

local function checkSpeaker()
    if not started then return end
    local now = C.speakerName()
    if now ~= lastSpeaker then
        if now == me then
            note("You're Quill's speaker now - your copy answers in guild chat.")
        elseif now then
            note("Quill's speaker is now " .. now .. ". Your copy listens and stays quiet.")
        end
        lastSpeaker = now
    end
end


-- ---- Sharing notes -------------------------------------------

-- Called by Quill.lua whenever this copy writes something in the notebook.
function C.shareNote(entry)
    entry.id = (me or "?") .. ":" .. entry.when .. ":" .. math.random(9999)
    if C.isBridgePC() then
        entry.delivered = true          -- it's already on the bridge PC
        return
    end
    entry.delivered = false
    send("NOTE", entry.id, entry.kind, entry.when, entry.name, entry.text, entry.patch)
end

local function haveNote(id)
    for _, entry in ipairs(QuillDB.inbox) do
        if entry.id == id then return entry end
    end
end

local function resendUndelivered()
    local count = 0
    for _, entry in ipairs(QuillDB.inbox) do
        if entry.delivered == false and entry.id and count < 30 then
            send("NOTE", entry.id, entry.kind, entry.when, entry.name, entry.text, entry.patch)
            count = count + 1
        end
    end
end

-- Delivered notes older than 14 days are tidied out of the notebook.
local function pruneNotebook()
    local keep, cutoff = {}, time() - 14 * 24 * 3600
    for _, entry in ipairs(QuillDB.inbox) do
        if not (entry.delivered and (entry.when or 0) < cutoff) then
            table.insert(keep, entry)
        end
    end
    QuillDB.inbox = keep
end


-- ---- Sharing what officers approved --------------------------
-- Only the bridge PC sends these. Anyone with an older copy keeps the new one.

local lastLearnedSend, learnedQueued = 0, false

-- Someone is behind: send everything once, at most every 30 seconds (requests in between share one send).
function C.queueLearned()
    if not C.isBridgePC() or learnedQueued then return end
    learnedQueued = true
    C_Timer.After(math.max(3, 30 - (time() - lastLearnedSend)), function()
        learnedQueued = false
        C.sendLearned()
    end)
end

function C.sendLearned()
    lastLearnedSend = time()
    local L, count = QuillLearned, 0
    local version = L.version or 0
    for _, item in ipairs(L.answers or {}) do
        send("LRN", version, "A", item.q, item.a, item.by, item.patch, item.when); count = count + 1
    end
    for _, item in ipairs(L.facts or {}) do
        send("LRN", version, "F", item.text, item.author); count = count + 1
    end
    for _, item in ipairs(L.jokes or {}) do
        send("LRN", version, "J", item.text, item.author); count = count + 1
    end
    for _, item in ipairs(L.announcements or {}) do
        send("LRN", version, "N", item.id, item.day, item.time, item.text, item.repeating and 1 or 0); count = count + 1
    end
    send("LRNEND", version, count)
end

local arriving                    -- learned answers being received: { version, count, answers, facts, jokes }

local function takeLearned(fields)
    local version = tonumber(fields[2]) or 0
    if version <= C.learnedVersion() then return end
    if not arriving or arriving.version ~= version then
        arriving = { version = version, count = 0, answers = {}, facts = {}, jokes = {}, announcements = {} }
    end
    local kind = fields[3]
    if kind == "A" then
        table.insert(arriving.answers, { q = fields[4], a = fields[5], by = fields[6], patch = fields[7],
                                         when = tonumber(fields[8]) })
    elseif kind == "F" then
        table.insert(arriving.facts, { text = fields[4], author = fields[5] })
    elseif kind == "J" then
        table.insert(arriving.jokes, { text = fields[4], author = fields[5] })
    elseif kind == "N" then
        table.insert(arriving.announcements, { id = fields[4], day = fields[5], time = fields[6], text = fields[7],
                                               repeating = fields[8] == "1" })
    end
    arriving.count = arriving.count + 1
end

local function finishLearned(fields)
    local version, count = tonumber(fields[2]) or 0, tonumber(fields[3]) or -1
    if arriving and arriving.version == version and arriving.count == count and version > C.learnedVersion() then
        QuillDB.learned = { version = version, answers = arriving.answers, facts = arriving.facts, jokes = arriving.jokes,
                            announcements = arriving.announcements }
        note("Got the latest approved answers from the officers' PC (" .. count .. " items).")
    end
    arriving = nil
end


-- ---- Receiving -----------------------------------------------

local function onStatus(sender, fields, kind)
    local wasBridge = peers[sender] and peers[sender].bridge
    peers[sender] = {
        since   = tonumber(fields[3]) or time(),
        beat    = tonumber(fields[11]) or HEARTBEAT,
        bridge  = fields[4] == "1",
        officer = fields[5] == "1",
        willing = fields[6] == "1",
        learned = tonumber(fields[7]) or 0,
        version = fields[8] or "",
        content = fields[9] or "",
        busy    = fields[10] == "1",
        seen    = time(),
    }
    local peer = peers[sender]
    if peer.bridge then QuillDB.officeSeen = time() end     -- this guild has a back office
    if kind == "HELLO" and started and (C.isBridgePC() or C.myPlace() <= FRONT) then
        -- Only the speaker, the next in line and the bridge PC answer, so a newcomer in a guild of 500
        -- gets a handful of replies, not 500. Everyone else is heard on their next heartbeat.
        C_Timer.After(1 + math.random() * 3, function() myStatus("HERE") end)   -- spread the replies out
    end
    if kind == "HELLO" and peer.bridge then
        C_Timer.After(3 + math.random() * 5, resendUndelivered)                 -- the bridge PC just arrived
    end
    if peer.bridge and not wasBridge and kind ~= "HELLO" then
        resendUndelivered()
    end
    if C.isBridgePC() and peer.learned < C.learnedVersion() then
        C.queueLearned()
    end
    if C.isBridgePC() and peer.content ~= "" and peer.content ~= C.contentHash() then
        C.queueContent()
    end
    C.checkVersion(sender, peer.version)
    checkSpeaker()
end

local handlers = {
    HELLO = function(sender, f) onStatus(sender, f, "HELLO") end,
    HERE  = function(sender, f) onStatus(sender, f, "HERE") end,
    PING  = function(sender, f) onStatus(sender, f, "PING") end,

    NOTE = function(sender, f)
        local id = f[2]
        if not haveNote(id) then
            table.insert(QuillDB.inbox, { id = id, kind = f[3], when = tonumber(f[4]), name = f[5], text = f[6],
                                          patch = f[7], delivered = C.isBridgePC() })
        end
        if C.isBridgePC() then send("GOT", id) end
    end,

    GOT = function(sender, f)
        local entry = haveNote(f[2])
        if entry then entry.delivered = true end
    end,

    CONTENT = function(sender, f) C.takeContent(sender, f) end,

    HUSH = function(sender, f)                      -- an officer hushed (or unhushed) Quill
        local peer = peers[sender]
        if not (peer and peer.officer) then return end
        QuillDB.hushUntil = tonumber(f[2]) or 0
        if QuillDB.hushUntil > time() then
            note(sender .. " hushed Quill for " .. (f[3] or "?") .. " minutes.")
        else
            note(sender .. " unhushed Quill.")
        end
    end,

    FIRED = function(sender, f)                     -- an announcement went out - don't repeat it after a handover
        QuillDB.fired = QuillDB.fired or {}
        if f[2] and f[2] ~= "" then QuillDB.fired[f[2]] = time() end
        if f[3] and f[3] ~= "" then QuillDB.fired[f[3]] = time() end
    end,
    LRN    = function(sender, f) takeLearned(f) end,
    LRNEND = function(sender, f) finishLearned(f) end,
}

local buffers = {}

local function receive(message, sender)
    local id, part, total, piece = message:match("^(%d+):(%d+)/(%d+):(.*)$")
    if not id then return end
    if peers[sender] then peers[sender].seen = time() end   -- any message at all means they're still here
    part, total = tonumber(part), tonumber(total)
    local key = sender .. ":" .. id
    local buffer = buffers[key] or {}
    buffers[key] = buffer
    buffer[part] = piece
    for n = 1, total do
        if not buffer[n] then return end           -- still waiting for pieces
    end
    buffers[key] = nil
    local fields = {}
    for field in (table.concat(buffer, "", 1, total) .. "\t"):gmatch("(.-)\t") do
        table.insert(fields, field)
    end
    local handler = handlers[fields[1]]
    if handler then handler(sender, fields) end
end



-- ---- Raids, hush, announcements ------------------------------

local lastBusy = false

-- "Busy" = inside a raid. A copy that isn't raiding is preferred as speaker.
function C.isBusy()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and kind == "raid" or false
end

-- An officer's /quill hush: tell every copy (0 = unhush).
function C.hush(untilTime, minutes)
    QuillDB.hushUntil = untilTime
    if untilTime > time() then
        note("Quill is hushed for " .. minutes .. " minutes in guild chat. /quill unhush to undo.")
    else
        note("Quill is unhushed.")
    end
    send("HUSH", untilTime, minutes)
end

-- An announcement went out: tell the others so a new speaker doesn't repeat it.
function C.shareFired(key, id)
    send("FIRED", key, id or "")
end

-- ---- Events --------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")      -- after every loading screen: in or out of a raid?

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        me = UnitName("player")
        -- A /reload keeps your place in the queue; a real login starts a new one.
        if not (QuillDB.loginAt and QuillDB.lastBeat and time() - QuillDB.lastBeat < 120) then
            QuillDB.loginAt = time()
        end
        QuillDB.lastBeat = time()
        pruneNotebook()
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        C_Timer.After(5, function()
            myStatus("HELLO")                  -- "I'm here" - the others answer with "HERE"
            C_Timer.After(6, function()        -- give them time to answer, then decide who speaks
                started = true
                checkSpeaker()
            end)
        end)
        -- Check in every 20 seconds; say "still here" when this copy's heartbeat is due (with a little
        -- randomness, so a whole raid that logged in together doesn't beat in the same second).
        local nextBeat = time() + HEARTBEAT
        C_Timer.NewTicker(20, function()
            QuillDB.lastBeat = time()
            for name, info in pairs(peers) do
                if not alive(info) then peers[name] = nil end
            end
            local wanted = pickBeat()
            if wanted < myBeat then nextBeat = math.min(nextBeat, time() + wanted) end   -- moved up the queue
            myBeat = wanted
            if time() >= nextBeat then
                myStatus("PING")
                nextBeat = time() + myBeat * (0.8 + math.random() * 0.4)
            end
            checkSpeaker()
        end)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = arg1, arg2, arg3, arg4
        if prefix ~= PREFIX or isSecret(message) or isSecret(sender) then return end
        sender = short(sender)
        if sender == me then return end
        receive(message, sender)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local busyNow = C.isBusy()
        if started and busyNow ~= lastBusy then myStatus("PING") end
        lastBusy = busyNow
        if started then checkSpeaker() end

    elseif event == "CHAT_MSG_SYSTEM" then
        if isSecret(arg1) then return end
        local text = arg1:gsub("|Hplayer:[^|]*|h%[?([^%]|]*)%]?|h", "%1")
        local gone = text:match("^(.-) has gone offline")
        if gone and peers[short(gone)] then
            peers[short(gone)] = nil
            checkSpeaker()
        end
    end
end)


-- ---- For /quill who and /quill speaker -----------------------

function C.announce()            -- tell the others straight away (after /quill speaker)
    if started then myStatus("PING") end
    checkSpeaker()
end

function C.describe()
    local speaker = C.speakerName()
    local function tag(info)
        local bits = {}
        if info.bridge then table.insert(bits, "bridge PC") end
        if info.officer then table.insert(bits, "officer") end
        if not info.willing then table.insert(bits, "speaker off") end
        return #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or ""
    end
    note("Speaker: " .. (speaker or "nobody") .. (speaker == me and " - that's you" or ""))
    note("  " .. (me or "?") .. " (you)" .. tag({ bridge = C.isBridgePC(), officer = C.isOfficer(), willing = QuillDB.speaker }))
    local count = 0
    for name, info in pairs(peers) do
        note("  " .. name .. tag(info))
        count = count + 1
    end
    if count == 0 then note("  No other copies of Quill online.") end
    local waiting = 0
    for _, entry in ipairs(QuillDB.inbox) do
        if entry.delivered == false then waiting = waiting + 1 end
    end
    if waiting > 0 then note(waiting .. " note(s) waiting to reach the officers' PC.") end
    note("Approved answers version: " .. C.learnedVersion())
end


-- ============================================================
--  Version nudge and shared content
-- ============================================================

-- ---- "A newer Quill is out" ----------------------------------

function C.addonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get("Quill", "Version") or "0"
end

local function newer(a, b)                -- is version a newer than b?  "0.10" beats "0.9"
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do table.insert(pa, tonumber(n)) end
    for n in tostring(b):gmatch("%d+") do table.insert(pb, tonumber(n)) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

local nudged = false
function C.checkVersion(sender, version)
    if nudged or version == "" or not newer(version, C.addonVersion()) then return end
    nudged = true                          -- once per session is plenty
    note("A newer Quill (v" .. version .. ") is out - you're on v" .. C.addonVersion() ..
         ". Ask an officer for the update.")
end


-- ---- Turning tables into text and back (data only - never code) ----
-- Strings are quoted with escapes, numbers end in ";", true/false are T/F, tables are { key value ... }.

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r", ["|"] = "\\p" }
local UNESCAPES = { ["\\"] = "\\", ['"'] = '"', t = "\t", n = "\n", r = "\r", p = "|" }

local function pack(value, out)
    local kind = type(value)
    if kind == "string" then
        table.insert(out, '"' .. value:gsub('[\\"\t\n\r|]', ESCAPES) .. '"')
    elseif kind == "number" then
        table.insert(out, "n" .. value .. ";")
    elseif kind == "boolean" then
        table.insert(out, value and "T" or "F")
    elseif kind == "table" then
        table.insert(out, "{")
        local keys = {}
        for key in pairs(value) do table.insert(keys, key) end
        table.sort(keys, function(x, y)                    -- same order every time, so the hash is stable
            if type(x) == type(y) then return x < y end
            return type(x) == "number"
        end)
        for _, key in ipairs(keys) do
            pack(key, out)
            pack(value[key], out)
        end
        table.insert(out, "}")
    end
end

local function packText(value)
    local out = {}
    pack(value, out)
    return table.concat(out)
end

local function unpackText(text)
    local pos = 1
    local function read()
        local c = text:sub(pos, pos)
        if c == '"' then
            local parts, i = {}, pos + 1
            while true do
                local ch = text:sub(i, i)
                if ch == "" then error("unfinished text") end
                if ch == '"' then break end
                if ch == "\\" then
                    local code = text:sub(i + 1, i + 1)
                    table.insert(parts, UNESCAPES[code] or code)
                    i = i + 2
                else
                    table.insert(parts, ch)
                    i = i + 1
                end
            end
            pos = i + 1
            return table.concat(parts)
        elseif c == "n" then
            local finish = text:find(";", pos, true)
            local number = tonumber(text:sub(pos + 1, finish - 1))
            pos = finish + 1
            return number
        elseif c == "T" or c == "F" then
            pos = pos + 1
            return c == "T"
        elseif c == "{" then
            pos = pos + 1
            local result = {}
            while text:sub(pos, pos) ~= "}" do
                if pos > #text then error("unfinished table") end
                local key = read()
                result[key] = read()
            end
            pos = pos + 1
            return result
        end
        error("unexpected '" .. c .. "'")
    end
    return read()
end

local function hashOf(text)                -- a short fingerprint: same text, same number
    local h = 7
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
    return tostring(h)
end


-- ---- Sharing the guild's words and settings ------------------
-- The bridge PC's QuillPhrases (greetings, jokes, small talk...) and QuillGuild (answers, raid hours, mood)
-- are the guild's master copy. Other copies take them over the hidden channel and use them instead of
-- whatever came in their zip. Only the words travel - never code.

local contentText, contentHash

local function masterContent()
    return { phrases = QuillPhrases, guild = QuillGuild }
end

function C.contentHash()
    if C.isBridgePC() then
        contentText = contentText or packText(masterContent())
        contentHash = contentHash or hashOf(contentText)
        return contentHash
    end
    return (QuillDB and QuillDB.content and QuillDB.content.hash) or "none"   -- "none" = can take content, has none yet
end

local lastContentSend, contentQueued = 0, false
function C.queueContent()
    if not C.isBridgePC() or contentQueued then return end
    contentQueued = true
    C_Timer.After(math.max(4, 60 - (time() - lastContentSend)), function()
        contentQueued = false
        lastContentSend = time()
        send("CONTENT", C.contentHash(), contentText)
    end)
end

local function applyContent(content)
    if type(content.phrases) == "table" and type(content.phrases.jokes) == "table" then
        QuillPhrases = content.phrases
    end
    if type(content.guild) == "table" then
        QuillGuild = content.guild
    end
end

function C.takeContent(sender, fields)
    if C.isBridgePC() then return end
    local hash, text = fields[2], fields[3] or ""
    if hash == C.contentHash() or hashOf(text) ~= hash then return end   -- already have it, or it arrived damaged
    local ok, content = pcall(unpackText, text)
    if not ok or type(content) ~= "table" then return end
    QuillDB.content = { hash = hash, data = content }
    applyContent(content)
    note("Updated Quill's jokes, greetings and guild answers from " .. sender .. "'s copy.")
end

-- At load: a copy that has received the guild's words before uses them straight away.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= "Quill" then return end
    if not C.isBridgePC() and QuillDB and QuillDB.content and QuillDB.content.data then
        applyContent(QuillDB.content.data)
    end
end)

C._pack, C._unpack, C._hash = packText, unpackText, hashOf     -- for testing
