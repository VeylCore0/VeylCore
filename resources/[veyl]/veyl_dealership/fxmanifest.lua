fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_dealership'
description 'VeylCore dealership: catalog, confirmed purchase through the core ledger, ownership registration and delivery'
version '0.1.0'

dependencies { '/onesync', 'veyl_lib', 'veyl_core', 'veyl_vehicles', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
