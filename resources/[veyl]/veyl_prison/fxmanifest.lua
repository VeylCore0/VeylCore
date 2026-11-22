fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_prison'
description 'VeylCore prison: persistent sentences, online countdown, yard work, escape prevention and controlled release'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }
