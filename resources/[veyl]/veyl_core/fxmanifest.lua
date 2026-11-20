fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_core'
author 'VeylCore'
description 'VeylCore core: players, characters, PlayerData, personal money, metadata, jobs/gangs, permissions, lifecycle'
version '0.2.0'

dependencies {
    '/onesync',
    'oxmysql',
}

shared_scripts {
    'lib/shared.lua',
    'config/shared.lua',
    'shared/loader.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'lib/server.lua',
    'config/server.lua',
    'server/migrations.lua',
    'server/groups.lua',
    'server/players.lua',
    'server/money.lua',
    'server/metadata.lua',
    'server/characters.lua',
    'server/permissions.lua',
    'server/paychecks.lua',
    'server/exports.lua',
    'bridge/qb/server.lua',
    'server/commands.lua',
}

client_scripts {
    'lib/client.lua',
    'config/client.lua',
    'client/playerdata.lua',
    'client/events.lua',
    'client/exports.lua',
    'bridge/qb/client.lua',
}

files {
    'lib/shared.lua',
    'lib/client.lua',
    'modules/playerdata.lua',
    'shared/jobs.lua',
    'shared/gangs.lua',
    'shared/vehicles.lua',
    'shared/weapons.lua',
    'shared/locations.lua',
}
