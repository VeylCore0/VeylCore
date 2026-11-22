-- veyl_apartments configuration. Money is whole dollars; times are real-world (server clock).

AptConfig = {
    -- How many active leases one character may hold.
    MaxLeasesPerCharacter = 1,

    -- Runtime routing buckets for private homes: BucketBase + unit id (never stored; recomputed every start).
    -- Tours use TourBucketBase + player id, so a tour never shares a world with residents.
    BucketBase = 41000,
    TourBucketBase = 46000,

    -- Entry rules (checked on the server).
    Entry = {
        -- 'walk': residents unlock their real door and walk in (the door relocks itself after AutoLockSeconds).
        -- 'teleport': the door stays locked and "Enter" moves you inside a private world (use this if the MLO door
        -- does not respond to the game's door system on your build).
        Mode = 'walk',
        AutoLockSeconds = 8,
        Distance = 3.0,               -- how close to the door you must be
        AllowWhileDead = false,
        BlockedStateBags = { 'restrained', 'cuffed', 'handcuffed' }, -- player state bags that block entering
        CollisionTimeoutMs = 7000,
    },

    -- When a resident's access is removed while they are inside: protected actions stop at once; after this many
    -- seconds they are walked back out through the door (a controlled exit). nil = let them leave on their own.
    RevokedExitSeconds = 20,

    -- Interior tours of vacant rooms: isolated world, no storage/furniture, original position restored.
    Tour = { Enabled = true, Seconds = 90 },

    Billing = {
        TickSeconds = 60,             -- how often the server looks for leases that are due (never per frame)
        ReminderHours = 24,           -- phone reminder this long before rent is due
        RetryHours = 6,               -- after a failed automatic payment, wait this long before trying again
        GraceDays = 3,                -- overdue this long -> the eviction policy applies
        EvictionPolicy = 'end_lease', -- 'end_lease' (storage + furniture go to recovery) or 'notify_only'
        RecoveryDays = 14,            -- former residents can claim their storage at the front desk for this long
        PendingLeaseMinutes = 2,      -- a lease whose first payment never confirmed is resolved after this
    },

    Roommates = { Max = 2, InviteHours = 24 },
    Guests = { MaxActive = 6, MaxHours = 72, DefaultHours = 4 },
    Doorbell = {
        RequestSeconds = 60,          -- a visit request expires after this
        PassMinutes = 15,             -- an approved request gives a single-visit pass this long
        CooldownSeconds = 20,         -- per visitor, per apartment
        MaxPendingPerApartment = 3,
    },

    -- Permissions a leaseholder may hand to a roommate (the leaseholder always has all of them).
    RoommatePermissions = { 'enter', 'storage', 'wardrobe', 'furniture', 'guests' },
    DefaultRoommatePermissions = { 'enter', 'storage', 'wardrobe', 'furniture' },

    Furniture = {
        SellBackRate = 0.5,           -- share of the price refunded when furniture is sold back
        MinSpacing = 0.35,            -- metres between object origins
    },

    Noticeboard = { TitleLength = 60, BodyLength = 400, Days = 7, PostCooldownSeconds = 60, MaxActivePerResident = 3, HideAfterReports = 3 },
    Maintenance = {
        Categories = { 'plumbing', 'electrical', 'appliance', 'pest', 'other' },
        StaffPermission = 'apartments.maintenance', -- ACE veyl.apartments.maintenance
        AccessMinutes = 60,
        NpcFallbackMinutes = 30,      -- nil = off. When no staff accept a request within this time, the front desk closes it.
    },
    Parcels = { KeepDays = 14 },

    -- Optional integrations. Each is used only if the resource is started.
    Integrations = { phone = 'veyl_phone', garages = 'veyl_garages', appearance = 'veyl_appearance', admin = 'veyl_admin' },
}

-- Apartment types. Only enable types backed by a real interior. The Starlite Motel MLO has ONE interior
-- (zydrec_sm_int, used by all 30 rooms), so it offers one type.
AptTypes = {
    starlite_room = {
        label = 'Starlite Room', description = 'A renovated motel room with a front window onto the walkway. Unfurnished: make it yours.',
        rent = 450, intervalDays = 7, deposit = 450, storage = { slots = 40, maxWeight = 150000 }, lockerSlots = 15,
        furnitureLimit = 25, image = 'starlite_room', amenities = { 'Private entrance', 'Front-desk parcels', 'Courtyard parking' },
    },
}

-- Buildings. Units come from data/*.lua (generated from the MLO).
AptBuildings = {
    starlite = {
        label = 'Starlite Motel', address = 'East Vinewood, Los Santos',
        mlo = 'zydrec-starlitemotel', units = 'StarliteUnits', type = 'starlite_room',
        blip = { sprite = 475, colour = 27, scale = 0.75 },
        -- The front desk (leasing, visitor directory, parcels, storage recovery, noticeboard). The motel MLO has no
        -- office interior, so the desk is an outdoor counter. Default: the middle of the courtyard, derived from the
        -- rooms' door positions; the ground height is found in game. Move it with /aptpos (see docs/APARTMENTS.md).
        frontDesk = { derive = 'courtyard', model = 'a_f_y_business_02' },
        -- No lobby, elevators, gym, laundry, rooftop or mailboxes exist in this MLO, so none are configured.
        elevators = nil,
        amenities = {},
        directory = true,          -- residents can opt in to the visitor directory
        parking = nil,             -- set to a veyl_garages garage id to link leases to a garage (see docs)
    },
}
