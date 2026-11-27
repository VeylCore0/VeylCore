-- Built-in app registry (PhoneConfig.Apps): what is installed, and the App Store install/uninstall.
-- Apps from other resources are registered on the client (exports.veyl_phone:RegisterApp) and are always shown.

Apps = {}
local byId = {}
for _, a in ipairs(PhoneConfig.Apps) do byId[a.id] = a end

function Apps.ListFor(settings)
    local installed = {}
    for _, id in ipairs(settings.installed or {}) do installed[id] = true end
    local out = {}
    for _, a in ipairs(PhoneConfig.Apps) do
        out[#out + 1] = {
            id = a.id, label = a.label, description = a.description, core = a.core == true, dock = a.dock == true,
            installed = a.core == true or installed[a.id] == true,
        }
    end
    return out
end

local function save(src, citizenid, settings)
    MySQL.update.await('UPDATE veyl_ph_accounts SET settings = ? WHERE citizenid = ?', { json.encode(settings), citizenid })
    Phone.sessions[src].settings = settings
end

--- appInstall(id, install): App Store install (true) / uninstall (false). Core apps cannot be removed.
Veyl.RegisterCallback('appInstall', function(src, citizenid, id, install)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local a = type(id) == 'string' and byId[id]
    if not a then return Veyl.Err('NOT_FOUND', 'Unknown app') end
    if a.core then return Veyl.Err('INVALID_STATE', 'This app is part of the phone') end
    local list = {}
    for _, x in ipairs(s.settings.installed) do if x ~= id then list[#list + 1] = x end end
    if install == true then list[#list + 1] = id end
    local merged = {}
    for k, v in pairs(s.settings) do merged[k] = v end
    merged.installed = list
    local clean = Phone.CleanSettings(merged)
    save(src, citizenid, clean)
    return Veyl.Ok({ apps = Apps.ListFor(clean) }, install == true and (a.label .. ' installed') or (a.label .. ' removed'))
end, { cooldown = 500 })

--- homeSave(order): the home-screen order (app ids; built-in and registered apps).
Veyl.RegisterCallback('homeSave', function(src, citizenid, order)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local merged = {}
    for k, v in pairs(s.settings) do merged[k] = v end
    merged.home = order
    local clean = Phone.CleanSettings(merged)
    save(src, citizenid, clean)
    return Veyl.Ok({ home = clean.home })
end, { cooldown = 500 })
