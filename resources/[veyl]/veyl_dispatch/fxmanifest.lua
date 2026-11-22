fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_dispatch'
description 'VeylCore dispatch: calls and blips for police and EMS, unit status and callsigns, panic button, /911 and /311'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
