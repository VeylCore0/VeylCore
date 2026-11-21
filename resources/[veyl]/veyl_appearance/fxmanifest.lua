fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_appearance'
description 'VeylCore appearance: character creator, clothing stores, barbers, outfits and appearance restoration'
version '0.4.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua', 'shared.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
