fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'ziks-bugreport'
author      'ziks'
description 'In-game bug reports with screenshot and full context, sent to a Discord webhook or ziks Dev Hub'
version     '1.1.0'
repository  'https://github.com/ziks29/ziks-bugreport'

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    'server/main.lua',
    'server/webhook.js',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependency 'screenshot-basic' -- also satisfied by screencapture (it provides 'screenshot-basic')
