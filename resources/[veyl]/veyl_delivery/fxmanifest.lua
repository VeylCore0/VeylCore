fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_delivery'
description 'VeylCore package delivery job: depot NPC, assigned van, randomized stops, validated one-time payout'
version '0.2.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui', 'veyl_interact', 'veyl_vehicles', 'veyl_vehiclekeys' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
