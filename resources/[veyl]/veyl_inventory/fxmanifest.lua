fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_inventory'
description 'VeylCore inventory adapter over ox_inventory: repeat-safe grants/removals, usable items, stashes'
version '0.2.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_interact', 'ox_inventory' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
