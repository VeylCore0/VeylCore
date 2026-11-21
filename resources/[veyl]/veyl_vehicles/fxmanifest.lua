fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_vehicles'
description 'VeylCore vehicle service: authorized server spawns, stable ids, owned-vehicle storage and cleanup ownership'
version '0.2.0'

dependencies { '/onesync', 'oxmysql', 'veyl_core' }

shared_script '@veyl_core/lib/shared.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'seatbelt.lua' }
