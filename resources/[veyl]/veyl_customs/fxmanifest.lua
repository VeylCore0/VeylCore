fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_customs'
description 'VeylCore vehicle customisation and mechanic business: preview sessions, Paint Studio, server-priced checkout, work orders, parts, dashboard, saved builds'
version '0.1.0'

dependencies { '/onesync', 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_vehicles', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'shared/config.lua', 'shared/catalog.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/bridge.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
