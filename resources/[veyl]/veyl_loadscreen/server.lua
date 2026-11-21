-- Hands the loading screen its settings and the live player count (read in the page as window.nuiHandoverData.veyl).

local function clean(list, max)
    local out = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        if #out >= max then break end
        out[#out + 1] = v
    end
    return out
end

local function safeUrl(url)
    return type(url) == 'string' and #url <= 200 and url:match('^https://[^%s"<>\']+$') and url or ''
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local c = LoadscreenConfig
    local tracks = {}
    for _, t in ipairs(clean(c.Music.Tracks, 30)) do
        if type(t.file) == 'string' and t.file:match('^music/[%w_%-%. ]+%.[mo][pg][3g]$') then
            tracks[#tracks + 1] = { title = tostring(t.title or 'Untitled'), artist = tostring(t.artist or ''), file = t.file }
        end
    end
    deferrals.handover({
        veyl = {
            headline = c.Headline, subtitle = c.Subtitle,
            players = c.ShowPlayerCount and #GetPlayers() or nil,
            maxPlayers = c.ShowPlayerCount and GetConvarInt('sv_maxclients', 48) or nil,
            updatesTitle = c.UpdatesTitle, updates = clean(c.Updates, 4),
            tips = clean(c.Tips, 30), tipSeconds = c.TipSeconds,
            discord = safeUrl(c.Links.Discord), rules = safeUrl(c.Links.Rules),
            music = { enabled = c.Music.Enabled ~= false, volume = c.Music.Volume, tracks = tracks },
        },
    })
end)
