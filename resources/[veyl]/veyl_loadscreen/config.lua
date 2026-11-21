-- veyl_loadscreen settings. Sent to the loading screen when a player connects (deferrals.handover),
-- so edits apply after a resource restart without rebuilding anything.
LoadscreenConfig = {
    Headline = { 'YOUR STORY.', 'STARTS HERE.' },  -- line 1 white, line 2 violet
    Subtitle = 'A new city. A new chapter.',

    -- Player count pill (top right). Shows the real count from the server; set false to hide it.
    ShowPlayerCount = true,

    -- "City updates" card. icon: briefcase | users | car | star | megaphone | home | shield | wrench
    UpdatesTitle = 'CITY UPDATES',
    Updates = {
        { icon = 'briefcase', text = 'New businesses are opening' },
        { icon = 'users', text = 'Explore the city and meet your crew' },
        { icon = 'car', text = 'Premium Deluxe Motorsport has new stock' },
    },

    -- Rotating tips under the progress bar (every TipSeconds).
    Tips = {
        'Get started at City Hall to find your first job.',
        'Press F1 to open your phone. Buy one at any General Store.',
        'Press F2 for your inventory. You can keep walking while it is open.',
        'Park your car at a garage to keep it safe. Abandoned vehicles end up at the impound lot.',
        'Need help? Use /report to reach staff.',
    },
    TipSeconds = 7,

    -- Buttons (bottom right). Leave a URL empty ('') to hide its button.
    Links = {
        Discord = '',        -- e.g. 'https://discord.gg/yourserver'
        Rules = '',          -- e.g. 'https://yourserver.com/rules'
    },

    -- Music. With no Tracks listed, "Veyl Radio" plays original tracks generated live in the browser
    -- (no audio files). To use your own music, put .mp3/.ogg files in web/music/ and list them here:
    --   { title = 'Midnight Drive', artist = 'Veyl Radio', file = 'music/midnight-drive.mp3' }
    Music = {
        Enabled = true,
        Volume = 0.35,       -- 0.0 - 1.0 starting volume
        Tracks = {},
    },
}
