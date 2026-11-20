fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_shops'
description 'VeylCore shops: server-owned prices, validated purchases, refunds and restart reconciliation'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui', 'veyl_interact', 'veyl_banking', 'veyl_inventory' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
