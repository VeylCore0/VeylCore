fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_boosting'
description 'VeylCore boosting: contracts, vehicle recovery missions, reputation ranks, heat, crews and a tablet'
version '2.0.0'

-- veyl_vehicles spawns the contract vehicles (the vehicle service of VeylCore); veyl_ui provides the shared notification/menu styles.
dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact', 'veyl_target', 'veyl_vehicles' }

shared_scripts {
    '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua',
    'config/main.lua', 'config/contracts.lua', 'config/vehicles.lua', 'config/progression.lua', 'config/heat.lua', 'config/crews.lua', 'config/locations.lua',
    'shared/constants.lua', 'shared/utils.lua',
}
server_scripts {
    '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua',
    'server/logging.lua', 'server/database.lua', 'server/security.lua', 'server/progression.lua',
    'integrations/dispatch_adapter.lua', 'server/heat.lua', 'server/crews.lua', 'server/contracts.lua', 'server/main.lua',
}
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua', 'client/contracts.lua', 'client/interactions.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
