fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_production'
description 'VeylCore production: supply shop, gathering, plants, portable workstations, player-owned laboratories, progression (fictional)'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact', 'veyl_target' }

shared_scripts {
    '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua',
    'config/main.lua', 'config/progression.lua', 'config/botanical.lua', 'config/field_operations.lua', 'config/supplier_operations.lua', 'config/workstations.lua', 'config/properties.lua', 'config/police.lua', 'config/street.lua', 'config/economy.lua',
    'shared/enums.lua', 'shared/items.lua', 'shared/utils.lua',
}
server_scripts {
    '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua',
    'server/crypto.lua', 'server/logging.lua', 'server/database.lua', 'server/security.lua', 'server/inventory.lua', 'server/progression.lua',
    'server/police.lua', 'server/plants.lua', 'server/workstations.lua', 'server/properties.lua', 'server/market.lua', 'server/crews.lua', 'server/shop.lua', 'server/farms.lua', 'server/gathering.lua', 'server/street.lua', 'server/admin.lua', 'server/supplier.lua', 'server/hazard.lua',
    'server/callbacks.lua', 'server/main.lua',
}
client_scripts {
    '@veyl_core/lib/client.lua',
    'client/main.lua', 'client/placement.lua', 'client/plants.lua', 'client/workstations.lua', 'client/properties.lua', 'client/interactions.lua', 'client/field.lua', 'client/supplier.lua', 'client/hazard.lua', 'client/admin.lua', 'client/street.lua',
}

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
