fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_vehicles'
description 'VeylCore vehicle service: authorized server spawns, keys/locks, fuel and cleanup ownership'
version '0.1.0'

dependencies { '/onesync', 'veyl_core', 'veyl_ui', 'veyl_banking', 'veyl_interact' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
