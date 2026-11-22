fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_mdt'
description 'VeylCore MDT: people and vehicle lookups, officer notes, warrants, vehicle flags, reports and sentencing'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
