fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_characters'
description 'VeylCore character slots, creation, selection and safe deletion'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
