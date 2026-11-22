fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_heists'
description 'VeylCore heists: six Fleeca banks, the Paleto bank and Vangelico, with police minimums, alarms and cooldowns'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }
