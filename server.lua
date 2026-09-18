local RSGCore = exports['rsg-core']:GetCoreObject()

local deadQueue = {}
local processedPeds = {}

RegisterNetEvent('torp_orderly:server:queueDeadPed', function(pedNetId)
    if processedPeds[pedNetId] then return end
    processedPeds[pedNetId] = true
    table.insert(deadQueue, pedNetId)
    TriggerClientEvent('torp_orderly:client:syncQueue', -1, deadQueue)
end)

RegisterNetEvent('torp_orderly:server:pedCleaned', function(pedNetId)
    processedPeds[pedNetId] = nil
    for i, id in ipairs(deadQueue) do
        if id == pedNetId then
            table.remove(deadQueue, i)
            break
        end
    end
    TriggerClientEvent('torp_orderly:client:syncQueue', -1, deadQueue)
end)
