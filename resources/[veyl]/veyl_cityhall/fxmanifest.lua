fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_cityhall'
description 'VeylCore City Hall: identity and licence cards, licences, the job board, showing ID to people nearby'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
