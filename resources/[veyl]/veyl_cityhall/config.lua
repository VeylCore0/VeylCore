-- veyl_cityhall configuration. Prices are whole dollars; the server decides every charge.

CityHallConfig = {
    -- The front desk. Stand within UseDistance of the clerk to use City Hall.
    Desk = {
        coords = vector4(-265.0, -963.6, 31.2, 205.0), -- Alta Street civic offices; move this to your City Hall MLO if you use one
        model = 'a_f_y_business_02',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip = { sprite = 419, colour = 0, scale = 0.75, name = 'City Hall' },
    },
    UseDistance = 3.0,
    PaymentMethods = { 'cash', 'bank' },

    -- Licences live on the character (metadata.licences). price = nil means City Hall cannot sell it: it is granted
    -- by staff or by the groups in GrantGroups (e.g. the police after a background check) with /licence.
    Licences = {
        driver   = { label = "Driver's licence", description = 'Lets you drive on public roads.', price = 500, order = 1 },
        weapon   = { label = 'Weapon licence', description = 'Issued by the police after a background check.', price = nil, order = 2 },
        business = { label = 'Business licence', description = 'Needed to own and run a registered business.', price = 2500, order = 3 },
    },

    -- Printed documents (inventory items). requires = the licence you must hold to get the card.
    Documents = {
        identity_card  = { label = 'Identity card', description = 'Proof of who you are.', price = 50, order = 1 },
        driver_license = { label = "Driver's licence card", description = 'Proof you can drive.', price = 75, requires = 'driver', order = 2 },
        weapon_license = { label = 'Weapon licence card', description = 'Proof you may carry a firearm.', price = 150, requires = 'weapon', order = 3 },
    },

    -- Who may grant or revoke licences with /licence <id> <licence> <on|off> (besides staff with veyl.cityhall.manage).
    -- [licence] = { [job] = minimum grade }
    GrantGroups = {
        weapon = { police = 2 },
        driver = { police = 1 },
    },

    -- Showing a card: everyone within this distance sees it for ShowSeconds.
    ShowDistance = 3.0,
    ShowSeconds = 8,

    -- Job board. Jobs marked open = true in veyl_core/shared/jobs.lua can be taken here; the rest show how to apply.
    JobBoard = {
        { job = 'delivery', description = 'Drive a GoPostal van and deliver parcels around the city. Paid per stop.',
          location = vector3(78.83, 111.95, 81.17), locationLabel = 'GoPostal depot, Downtown Vinewood' },
        { job = 'police', description = 'Protect and serve. Applications are reviewed by command staff.', apply = 'Apply in person at Mission Row PD.',
          location = vector3(441.0, -981.9, 30.7), locationLabel = 'Mission Row Police Department' },
        { job = 'ambulance', description = 'Respond to emergencies and treat patients.', apply = 'Apply in person at Pillbox Hill Medical Center.',
          location = vector3(298.6, -584.5, 43.3), locationLabel = 'Pillbox Hill Medical Center' },
        { job = 'mechanic', description = 'Repair and customise vehicles at LS Customs.', apply = 'Ask the shop owner for an interview.',
          location = vector3(-347.3, -133.5, 39.0), locationLabel = 'LS Customs, Burton' },
        { job = 'weazel', description = 'Report on the city for Weazel News and publish to every phone.', apply = 'Apply through the Jobs app on your phone.',
          location = vector3(-598.9, -929.9, 23.9), locationLabel = 'Weazel Plaza, Little Seoul' },
    },
}
