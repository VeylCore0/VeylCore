fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_cartheft'
description 'VeylCore car theft: ambient cars are locked; threaten a driver for the keys, or lockpick and hotwire a parked car; random loot in trunks and gloveboxes'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_target', 'veyl_minigames', 'veyl_vehicles' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
