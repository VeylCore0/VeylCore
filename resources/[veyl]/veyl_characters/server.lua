-- veyl_characters server: UI transport only. veyl_core validates slots, ownership, creation, deletion and login.

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function core(name, ...)
    return Veyl.Await('veyl_core', name, 20000, ...)
end

Veyl.RegisterCallback('list', function(src)
    return core('ListCharacters', src)
end, { requireCharacter = false, cooldown = 500 })

Veyl.RegisterCallback('create', function(src, _, data)
    if type(data) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Missing details') end
    local res = core('CreateCharacter', src, {
        firstname = data.firstname, lastname = data.lastname, birthdate = data.birthdate,
        gender = data.gender == 'f' and 1 or 0, nationality = data.nationality,
    })
    if not res.ok then return res end
    local list = core('ListCharacters', src)
    return Veyl.Ok({ citizenid = res.data.citizenid, characters = list.ok and list.data.characters or {} }, res.message)
end, { requireCharacter = false, cooldown = 1500 })

Veyl.RegisterCallback('select', function(src, _, citizenid)
    if not Veyl.Validate.str(citizenid, 1, 16) then return Veyl.Err('INVALID_INPUT', 'Invalid character') end
    return core('LoginCharacter', src, citizenid)
end, { requireCharacter = false, cooldown = 1500 })

Veyl.RegisterCallback('delete', function(src, _, citizenid, confirmName)
    if not Veyl.Validate.str(citizenid, 1, 16) then return Veyl.Err('INVALID_INPUT', 'Invalid character') end
    local res = core('DeleteCharacter', src, citizenid, tostring(confirmName or ''))
    if not res.ok then return res end
    local list = core('ListCharacters', src)
    return Veyl.Ok({ characters = list.ok and list.data.characters or {} }, res.message)
end, { requireCharacter = false, cooldown = 2000 })

RegisterNetEvent('veyl_characters:quit', function()
    local src = source
    if not Veyl.GetCitizenId(src) then DropPlayer(src, 'Left from character selection') end
end)
