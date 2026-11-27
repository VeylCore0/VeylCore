-- Tablet item (veyl_inventory `phone_tablet` use handler): a small menu for the MDT, dispatch and your home panel.
CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    exports.veyl_inventory:RegisterUseHandler('phone_tablet', function(ctx) TriggerClientEvent('veyl_phone:tablet', ctx.source) end)
end)
