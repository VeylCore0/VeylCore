fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_business'
description 'VeylCore businesses: ownership, business account, ingredient orders, stockroom, workstations and register sales'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua' }
