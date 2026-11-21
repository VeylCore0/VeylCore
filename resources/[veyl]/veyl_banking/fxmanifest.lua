fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_banking'
description 'VeylCore banking screen: overview, accounts, confirmed transfers, paged history (money owned by veyl_core)'
version '0.4.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
