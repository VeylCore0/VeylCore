-- Tablet item menu. Each entry only appears when its resource runs and your job may use it.
RegisterNetEvent('veyl_phone:tablet', function()
    local T = PhoneConfig.Tablet
    local job = Veyl.PlayerData and Veyl.PlayerData.job or {}
    local options = {}
    if GetResourceState('veyl_mdt') == 'started' and (job.type == 'leo' or job.type == 'ems' or job.type == 'doj') then
        options[#options + 1] = { id = 'mdt', label = 'MDT', icon = 'shield' }
    end
    if GetResourceState('veyl_dispatch') == 'started' and (job.type == 'leo' or job.type == 'ems') then
        options[#options + 1] = { id = 'dispatch', label = 'Dispatch', icon = 'radio' }
    end
    if GetResourceState('veyl_apartments') == 'started' then options[#options + 1] = { id = 'home', label = 'My home', icon = 'home' } end
    options[#options + 1] = { id = 'phone', label = 'Phone', icon = 'phone' }
    vlib.registerMenu({ id = 'veyl_tablet', title = 'Tablet', options = options }, function(id)
        if id == 'mdt' then ExecuteCommand(T.Mdt)
        elseif id == 'dispatch' then ExecuteCommand(T.Dispatch)
        elseif id == 'home' then TriggerEvent('veyl_apartments:openPanel')
        elseif id == 'phone' then exports.veyl_phone:Open() end
    end)
    vlib.showMenu('veyl_tablet')
end)
