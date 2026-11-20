fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_needs'
description 'VeylCore persisted hunger, thirst and stress with consumable effects'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
