fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_ui'
description 'VeylCore UI compatibility layer: forwards notify/progress/confirm/input/menu to veyl_lib'
version '0.3.0'

dependencies { 'veyl_core', 'veyl_lib' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts {
    '@veyl_core/lib/client.lua',
    'client/provider_veyl.lua',
    'client/provider_vlib.lua',
    'client/main.lua',
}

ui_page 'web/index.html'
files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}
