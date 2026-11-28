fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_blackmarket'
description 'VeylCore black market: every illegal item (guns, drugs, burglary and hacking gear, lab supplies) sold by shady dealers through a custom menu'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
