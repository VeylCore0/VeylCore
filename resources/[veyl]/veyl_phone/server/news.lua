-- News: Weazel News stories and breaking alerts.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- News (Weazel News)
---------------------------------------------------------------------------
local function isReporter(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    for _, j in ipairs(C.News.Jobs) do if pd.job.name == j then return true, pd end end
    return false
end

Veyl.RegisterCallback('newsList', function(src)
    local _, err = session(src)
    if err then return err end
    local rows = MySQL.query.await('SELECT id, author, title, body, breaking, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_news ORDER BY id DESC LIMIT 40') or {}
    return Veyl.Ok({ articles = rows, reporter = isReporter(src) })
end, { cooldown = 500 })

Veyl.RegisterCallback('newsPost', function(src, citizenid, title, body, breaking)
    local _, err = session(src)
    if err then return err end
    local ok, pd = isReporter(src)
    if not ok then return Veyl.Err('NO_PERMISSION', 'Only on-duty Weazel News reporters can publish') end
    title, body = PhoneUtil.Clean(title, 120), tostring(body or ''):sub(1, 4000)
    if not title or #title < 5 or #body < 20 then return Veyl.Err('INVALID_INPUT', 'Write a headline and a story') end
    MySQL.insert.await('INSERT INTO veyl_phone_news (author_cid, author, title, body, breaking) VALUES (?, ?, ?, ?, ?)', { citizenid, charName(pd), title, body, breaking == true and 1 or 0 })
    if breaking == true then
        for _, p in ipairs(GetPlayers()) do
            local cid = Veyl.GetCitizenId(tonumber(p))
            if cid then Notify.Send(cid, { app = 'news', title = 'BREAKING · Weazel News', body = title, route = 'news' }) end
        end
    end
    Veyl.Audit(src, 'news_post', { title = title, breaking = breaking == true })
    return Veyl.Ok(nil, 'Published')
end, { cooldown = 10000 })
