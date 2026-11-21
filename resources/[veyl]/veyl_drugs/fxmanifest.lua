fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_drugs'
description 'VeylCore criminal enterprise (fictional): grow-anywhere plants, quality, persistence. Milestones A-B.'
version '0.1.0'

dependencies { '/onesync', 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config/main.lua', 'config/products.lua', 'shared/growth.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/core.lua', 'server/plants.lua', 'server/items.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/ui.lua', 'client/plants.lua', 'client/placement.lua', 'client/supplier.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
