fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_inventory'
description 'VeylCore inventory facade with the built-in provider: item use/give/remove, stashes and repeat-safe grants'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui', 'veyl_interact' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua', 'items.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/provider_builtin.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
