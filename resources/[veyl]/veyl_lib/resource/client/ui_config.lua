-- veyl_lib notifications and progress: look and behaviour. Sent to the page when it loads.
-- Colours match the Ocean Drive HUD (veyl_hud); change them here to restyle every notification and progress bar.

VlibUIConfig = {
    Theme = {
        background = '#151D22', backgroundOpacity = 0.86,   -- card colour and how solid it is (0.5 - 1)
        text = '#F7FAFC', textSecondary = '#AAB6BF',
        success = '#A5F3D0', info = '#8BD4EE', warning = '#F0C374', error = '#EF9298',
        scale = 1.0,                                       -- UI scale (0.75 - 1.5)
        reducedMotion = false,                             -- no slide / fade animations
    },

    Notifications = {
        position = 'top-right',          -- 'top-right' | 'top-left' | 'top-center'
        offsetX = 1.6, offsetY = 3.0,    -- % of the screen from that corner (keep clear of the HUD)
        width = 23,                      -- rem (about 370 px at 1080p)
        maxVisible = 4,                  -- more are queued
        maxQueue = 20,                   -- the oldest queued message is dropped beyond this
        defaultDuration = 5000,          -- ms
        minDuration = 1500, maxDuration = 30000,
        duplicates = 'merge',            -- 'merge' (counter ×2, ×3 …) or 'stack'
        restartOnUpdate = true,          -- a merged duplicate / UpdateNotification restarts the timer
        sound = true, volume = 0.35,     -- short soft tone per type (0 - 1)
        dismissKey = '',                 -- optional key (Settings → Key Bindings → FiveM) to dismiss the newest card
    },

    Progress = {
        position = 'bottom-center',
        offsetY = 11.0,                  -- % from the bottom of the screen
        width = 26,                      -- rem
        cancelControl = 73,              -- GTA control index for cancelling (73 = X)
        cancelLabel = 'X',
        completeMs = 900,                -- how long the "done" state shows (0 = off)
        minDuration = 250, maxDuration = 120000,
    },

    Hold = {
        control = 38, label = 'E',       -- default key for hold-to-interact (38 = E)
        releaseText = 'Release to cancel',
    },
}
