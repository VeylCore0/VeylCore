fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- Optional QBCore compatibility shim backed by veyl_core. It is the ONLY resource that may use the
-- 'qb-core' name: never start upstream qb-core beside it. Supported APIs: docs/COMPATIBILITY.md
name 'qb-core'
author 'VeylCore'
description 'VeylCore QBCore compatibility shim (subset). Not upstream qb-core.'
version '0.2.0'

dependency 'veyl_core'

shared_script 'shared/locale.lua'
server_script 'server.lua'
client_script 'client.lua'

files { 'shared/locale.lua' }
