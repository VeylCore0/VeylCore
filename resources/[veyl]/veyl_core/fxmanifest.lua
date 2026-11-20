fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_core'
author 'VeylCore'
description 'VeylCore: accounts, sessions, character lifecycle, permissions, audit and the shared Veyl library'
version '0.1.0'

dependencies {
    '/onesync',
    'oxmysql',
}

shared_scripts {
    'lib/shared.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'lib/server.lua',
    'server/main.lua',
    'server/commands.lua',
}

client_scripts {
    'lib/client.lua',
    'client/main.lua',
}

-- lib/* are imported by other resources with '@veyl_core/lib/<file>.lua'
files {
    'lib/shared.lua',
    'lib/client.lua',
}
