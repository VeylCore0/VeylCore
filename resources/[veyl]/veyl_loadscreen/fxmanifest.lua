fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_loadscreen'
description 'VeylCore loading screen: real load progress, live player count, city updates, tips and Veyl Radio'
version '1.0.0'

loadscreen 'web/index.html'
loadscreen_cursor 'yes'

server_scripts { 'config.lua', 'server.lua' }

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/radio.js',
    'web/assets/*',
    'web/fonts/*',
    'web/music/*',
}
