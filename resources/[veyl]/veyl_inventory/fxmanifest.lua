fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_inventory'
author 'VeylCore'
description 'VeylCore inventory engine: server-owned items, slots, metadata, transactional transfers, stashes, item use'
version '0.3.0'

-- Native profile: veyl_lib + SQL driver + the VeylCore adapter. Do NOT run ox_inventory at the same time.
dependencies { 'veyl_lib', 'oxmysql', 'veyl_core' }

shared_scripts { '@veyl_lib/init.lua', 'config.lua' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/items.lua',
    'server/db.lua',
    'server/store.lua',
    'server/containers.lua',
    'server/operations.lua',
    'server/use.lua',
    'server/stashes.lua',
    'server/drops.lua',
    'server/sessions.lua',
    'server/cash.lua',
    'server/adapter_veylcore.lua',
    'server/exports.lua',
    'server/weapons.lua',
}

client_scripts {
    'client/state.lua',
    'client/ui.lua',
    'client/use.lua',
    'client/stashes.lua',
    'client/drops.lua',
    'client/weapons.lua',
    'client/equipment.lua',
}

ui_page 'web/dist/index.html'
files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/images/*.png',
    'web/images/*.svg',
}
