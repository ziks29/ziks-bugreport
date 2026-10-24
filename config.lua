Config = {}

-- The Discord webhook URL is NOT set here. Put it in server.cfg (server-only, never sent to players):
--   set ziks_bugreport_webhook "https://discord.com/api/webhooks/123/abc"
-- Use `set`, never `setr`: `setr` replicates the value to every client.

Config.Locale   = 'en'          -- 'en' | 'ru'
Config.Key      = 'F9'          -- default key (players can rebind it in GTA settings > Key Bindings > FiveM)
Config.Command  = 'bug'         -- chat command with the same effect

Config.Cooldown   = 120         -- seconds between reports per player
Config.HourlyCap  = 6           -- max reports per player per hour

-- Who may pick a severity. Everyone else always sends "normal".
--   add_ace group.admin ziks-bugreport.severity allow
Config.SeverityAce    = 'ziks-bugreport.severity'
Config.SeverityForAll = false   -- true = every player can pick a severity

-- Ping a role for serious reports (role IDs, '' = no ping)
Config.PingRoles = { critical = '', high = '' }

-- Forum channel mode: point the webhook at a Discord *forum* channel and every report
-- becomes its own post (thread) you can discuss, tag and close.
Config.Forum = false
Config.ForumTags = {            -- optional forum tag IDs applied to new posts
    -- low = '', normal = '', high = '', critical = '',
}

-- What gets attached. Everything is server-side and goes only to your webhook.
Config.Attach = {
    screenshot  = true,  -- player can still untick it in the form
    reportFile  = true,  -- report-<time>.txt: environment, server console errors, F8 paste, resources
    playerData  = true,  -- player-<id>.json: framework player data + identifiers (IP is never included)
    inventory   = true,  -- inventory list in the report file (ox_inventory / qb / esx)
    console     = true,  -- recent server console output + errors
    resources   = true,  -- started resources with versions
}

Config.Screenshot = { quality = 0.92, maxBytes = 8100000 } -- base64 cap; Discord's limit is 10 MB per message

Config.Categories = {
    { id = 'ui',       en = 'UI / Menu',    ru = 'Интерфейс' },
    { id = 'vehicle',  en = 'Vehicle',      ru = 'Транспорт' },
    { id = 'job',      en = 'Job',          ru = 'Работа' },
    { id = 'housing',  en = 'Housing',      ru = 'Жильё' },
    { id = 'inventory',en = 'Inventory',    ru = 'Инвентарь' },
    { id = 'world',    en = 'World / Map',  ru = 'Мир / карта' },
    { id = 'other',    en = 'Other',        ru = 'Другое' },
}

Config.Text = {
    en = {
        title = 'Bug report', subtitle = 'Your position, player info and a screenshot are sent with the report.',
        t_title = 'Short title', t_desc = 'What happened?', t_steps = 'Steps to reproduce', t_expected = 'Expected', t_actual = 'Actual',
        category = 'Category', severity = 'Severity', low = 'Low', normal = 'Normal', high = 'High', critical = 'Critical',
        screenshot = 'Attach screenshot', retake = 'Retake', send = 'Send', cancel = 'Cancel', sending = 'Sending…',
        need_title = 'Enter a title', sent = 'Report sent. Thank you!', queued = 'Discord is busy - your report is saved and will be sent shortly.',
        failed = 'Could not send the report, try again later', cooldown = 'Wait %s s before the next report',
        capped = 'Hourly report limit reached', noshot = 'No screenshot yet. Press "Take" to capture', take = 'Take',
        shot_failed = 'Screenshot failed (see F8 console)', hint = 'Drag on the image to select an area', reset = 'Full screen',
        area = 'Area selected', ctx = 'Sent with the report', k_pos = 'Position', k_street = 'Street', k_zone = 'Zone', k_fps = 'FPS',
        k_hp = 'Health / armor', k_veh = 'Vehicle', preview = 'Screenshot', t_console = 'Paste errors from the F8 console (optional)',
        k_auto = 'Also: time, weather, what you look at, job, inventory, ping, game build, server errors, resources',
        -- Discord embed labels
        e_category = 'Category', e_severity = 'Severity', e_reporter = 'Reporter', e_location = 'Location', e_vehicle = 'Vehicle',
        e_client = 'Client', e_steps = 'Steps to reproduce', e_expected = 'Expected', e_actual = 'Actual', e_none = 'No description',
    },
    ru = {
        title = 'Баг-репорт', subtitle = 'Вместе с отчётом отправляются ваша позиция, данные игрока и скриншот.',
        t_title = 'Краткое название', t_desc = 'Что произошло?', t_steps = 'Шаги воспроизведения', t_expected = 'Ожидалось', t_actual = 'Получилось',
        category = 'Категория', severity = 'Серьёзность', low = 'Низкая', normal = 'Обычная', high = 'Высокая', critical = 'Критичная',
        screenshot = 'Приложить скриншот', retake = 'Переснять', send = 'Отправить', cancel = 'Отмена', sending = 'Отправка…',
        need_title = 'Введите название', sent = 'Репорт отправлен. Спасибо!', queued = 'Discord занят - репорт сохранён и скоро уйдёт.',
        failed = 'Не удалось отправить, попробуйте позже', cooldown = 'Подождите %s с до следующего репорта',
        capped = 'Достигнут часовой лимит репортов', noshot = 'Скриншота нет. Нажмите «Снять»', take = 'Снять',
        shot_failed = 'Не удалось снять скриншот (см. консоль F8)', hint = 'Выделите область мышью на изображении', reset = 'Весь экран',
        area = 'Выбрана область', ctx = 'Уйдёт вместе с репортом', k_pos = 'Позиция', k_street = 'Улица', k_zone = 'Район', k_fps = 'FPS',
        k_hp = 'Здоровье / броня', k_veh = 'Транспорт', preview = 'Скриншот', t_console = 'Вставьте ошибки из консоли F8 (необязательно)',
        k_auto = 'Также: время, погода, на что смотрите, работа, инвентарь, пинг, билд, ошибки сервера, ресурсы',
        e_category = 'Категория', e_severity = 'Серьёзность', e_reporter = 'Игрок', e_location = 'Место', e_vehicle = 'Транспорт',
        e_client = 'Клиент', e_steps = 'Шаги воспроизведения', e_expected = 'Ожидалось', e_actual = 'Получилось', e_none = 'Без описания',
    },
}
