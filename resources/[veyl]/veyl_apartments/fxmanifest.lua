fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_apartments'
description 'VeylCore apartments: leasing, private homes (Starlite Motel MLO), keys, roommates, visitors, storage, wardrobe, furniture'
version '1.0.0'

-- zydrec-starlitemotel provides the 30 physical rooms this resource manages (data/starlite.lua is generated from it).
dependencies { '/onesync', 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact', 'zydrec-starlitemotel' }

shared_scripts {
    '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua',
    'config.lua', 'data/starlite.lua', 'shared/geometry.lua', 'shared/furniture.lua',
}
server_scripts {
    '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua',
    'server/core.lua', 'server/access.lua', 'server/storage.lua', 'server/leases.lua', 'server/presence.lua',
    'server/people.lua', 'server/furniture.lua', 'server/community.lua', 'server/admin.lua',
}
client_scripts { '@veyl_core/lib/client.lua', 'client/ui.lua', 'client/main.lua', 'client/furniture.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
