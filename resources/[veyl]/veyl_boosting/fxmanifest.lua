fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_boosting'
description 'VeylCore boosting: car theft contracts by class and reputation, hotwiring, trackers that ping the police, drop-offs'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_vehicles', 'veyl_inventory', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }
