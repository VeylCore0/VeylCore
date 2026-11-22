fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_crime'
description 'VeylCore crime: dark web black market and dead drops, fence, laundering, drug corners, turf and tags, gang stashes, drug labs and branding'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_inventory', 'veyl_interact', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }
