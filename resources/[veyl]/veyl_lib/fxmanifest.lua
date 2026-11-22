fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_lib'
author 'VeylCore'
description 'VeylCore utility library: vlib/vcache modules, custom menus/dialogs/notify/progress, focus broker, callbacks, zones'
version '0.3.0'

-- veyl_lib depends on nothing VeylCore-specific: it must work without a logged-in character, core or inventory.

client_scripts {
    'init.lua',
    'resource/client/ui_config.lua',
    'resource/client/host.lua',
}

server_scripts {
    'init.lua',
    'resource/server/host.lua',
}

ui_page 'web/dist/index.html'

files {
    'init.lua',
    'modules/**/*.lua',
    'web/dist/index.html',
    'web/dist/assets/*',
}
