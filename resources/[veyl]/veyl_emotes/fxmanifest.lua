fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_emotes'
description 'VeylCore emotes: searchable menu, favourites, props, shared emotes (handshake, high five, hug)'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua', 'shared/emotes.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
