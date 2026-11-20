fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_ui'
description 'VeylCore UI routing: notifications, progress, confirm, input and menus (ox_lib or VeylCore NUI) with focus ownership'
version '0.2.0'

dependencies { 'veyl_core', 'ox_lib' }

shared_scripts { '@ox_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts {
    '@veyl_core/lib/client.lua',
    'client/provider_veyl.lua',
    'client/provider_oxlib.lua',
    'client/main.lua',
}

ui_page 'web/index.html'
files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}
