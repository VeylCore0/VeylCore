-- veyl_appearance server: owns saved appearance per character.

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_appearance',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_appearance (
                    character_id INT UNSIGNED NOT NULL,
                    model VARCHAR(32) NOT NULL,
                    data LONGTEXT NOT NULL,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (character_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local allowedModels = {}
for _, m in pairs(AppearanceConfig.Models) do allowedModels[m] = true end

Veyl.RegisterCallback('get', function(src, charId)
    local row = MySQL.single.await('SELECT model, data FROM veyl_appearance WHERE character_id = ?', { charId })
    if not row then return Veyl.Ok(nil) end
    local ok, data = pcall(json.decode, row.data)
    if not ok or type(data) ~= 'table' then return Veyl.Ok(nil) end
    data.model = row.model
    return Veyl.Ok(data)
end, { cooldown = 500 })

local function cleanList(list, maxId)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, e in ipairs(list) do
        if #out >= 20 then break end
        if type(e) == 'table' and Veyl.Validate.int(e.id, 0, maxId) and Veyl.Validate.int(e.d, -1, 1000)
            and Veyl.Validate.int(e.t, 0, 255) then
            out[#out + 1] = { id = e.id, d = e.d, t = e.t }
        end
    end
    return out
end

local function cleanAppearance(input)
    if type(input) ~= 'table' or not allowedModels[input.model] then return nil end
    local hb = type(input.headBlend) == 'table' and input.headBlend or {}
    local hair = type(input.hair) == 'table' and input.hair or {}
    return {
        model = input.model,
        components = cleanList(input.components, 11),
        props = cleanList(input.props, 7),
        headBlend = {
            mother = Veyl.Validate.int(hb.mother, 0, 45) and hb.mother or 21,
            father = Veyl.Validate.int(hb.father, 0, 45) and hb.father or 0,
            shapeMix = Veyl.Validate.int(hb.shapeMix, 0, 100) and hb.shapeMix or 50,
            skinMix = Veyl.Validate.int(hb.skinMix, 0, 100) and hb.skinMix or 50,
        },
        hair = {
            color = Veyl.Validate.int(hair.color, 0, 63) and hair.color or 0,
            highlight = Veyl.Validate.int(hair.highlight, 0, 63) and hair.highlight or 0,
        },
    }
end

Veyl.RegisterCallback('save', function(src, charId, input)
    local data = cleanAppearance(input)
    if not data then return Veyl.Err('INVALID_INPUT', 'Invalid appearance data') end
    local model = data.model
    data.model = nil
    MySQL.query.await([[INSERT INTO veyl_appearance (character_id, model, data) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE model = VALUES(model), data = VALUES(data)]], { charId, model, json.encode(data) })
    return Veyl.Ok(nil, 'Appearance saved')
end, { cooldown = 2000 })
