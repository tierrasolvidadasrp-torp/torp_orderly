local RSGCore = exports['rsg-core']:GetCoreObject()

local deadQueue = {}
local isBusy    = false
local kidPed    = 0

local function spawnKid()
    if DoesEntityExist(kidPed) then
        DeleteEntity(kidPed)
        kidPed = 0
    end

    RequestModel(Config.KidModel)
    local t = GetGameTimer() + 6000
    while not HasModelLoaded(Config.KidModel) do
        Wait(10)
        if GetGameTimer() > t then return end
    end

    kidPed = CreatePed(Config.KidModel,
        Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z - 1.0, Config.SpawnCoords.w,
        false, false, false, false)

    SetEntityInvincible(kidPed, true)
    SetBlockingOfNonTemporaryEvents(kidPed, true)
    SetPedFleeAttributes(kidPed, 0, false)
    Citizen.InvokeNative(0x283978A15512B2FE, kidPed, true)
    Citizen.InvokeNative(0x18FF3110CF47115D, kidPed, 9, true)
    FreezeEntityPosition(kidPed, true)
end

RegisterNetEvent('torp_orderly:client:syncQueue', function(q)
    deadQueue = q
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if DoesEntityExist(kidPed) then
            DeleteEntity(kidPed)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(3000)
        local playerCoords = GetEntityCoords(PlayerPedId())
        local dist = #(playerCoords - vec3(Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z))

        if dist < Config.SpawnDistance and not DoesEntityExist(kidPed) then
            spawnKid()
        end

        if dist > Config.DespawnDistance and DoesEntityExist(kidPed) and not isBusy then
            DeleteEntity(kidPed)
            kidPed = 0
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(3000)
        local peds = GetGamePool('CPed')
        for _, ped in ipairs(peds) do
            if IsEntityDead(ped) and not IsPedAPlayer(ped) and GetEntityModel(ped) ~= Config.KidModel then
                local coords = GetEntityCoords(ped)
                local distToDrop = #(coords - vec3(Config.DropCoords.x, Config.DropCoords.y, Config.DropCoords.z))
                if distToDrop > Config.ExclusionRadius and #(coords - vec3(Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z)) < Config.DetectionRadius then
                    if not NetworkGetEntityIsNetworked(ped) then
                        NetworkRegisterEntityAsNetworked(ped)
                    end
                    local netId = PedToNet(ped)
                    if netId ~= 0 then
                        local found = false
                        for _, id in ipairs(deadQueue) do
                            if id == netId then found = true; break end
                        end
                        if not found then
                            TriggerServerEvent('torp_orderly:server:queueDeadPed', netId)
                        end
                    end
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(1000)

        if DoesEntityExist(kidPed) and not isBusy and #deadQueue > 0 then
            isBusy = true

            local kidCoords    = GetEntityCoords(kidPed)
            local closestNetId = nil
            local closestDist  = math.huge

            for _, netId in ipairs(deadQueue) do
                local ped = NetToPed(netId)
                if DoesEntityExist(ped) and IsEntityDead(ped) then
                    local pCoords = GetEntityCoords(ped)
                    local distToDrop = #(pCoords - vec3(Config.DropCoords.x, Config.DropCoords.y, Config.DropCoords.z))
                    if distToDrop > Config.ExclusionRadius then
                        local d = #(pCoords - kidCoords)
                        if d < closestDist then
                            closestDist  = d
                            closestNetId = netId
                        end
                    else
                        TriggerServerEvent('torp_orderly:server:pedCleaned', netId)
                    end
                end
            end

            if not closestNetId then
                for _, netId in ipairs(deadQueue) do
                    TriggerServerEvent('torp_orderly:server:pedCleaned', netId)
                end
                isBusy = false
                goto continue
            end

            local targetNetId = closestNetId
            local targetPed   = NetToPed(targetNetId)

            if DoesEntityExist(targetPed) then
                local tCoords = GetEntityCoords(targetPed)

                FreezeEntityPosition(kidPed, false)
                TaskGoToCoordAnyMeans(kidPed, tCoords.x, tCoords.y, tCoords.z, 1.5, 0, 0, 786603, 0xbf800000)

                local timeout = GetGameTimer() + 60000
                while DoesEntityExist(targetPed) and #(GetEntityCoords(kidPed) - GetEntityCoords(targetPed)) > 2.5 do
                    Wait(500)
                    if GetGameTimer() > timeout then break end
                end

                if DoesEntityExist(targetPed) and #(GetEntityCoords(kidPed) - GetEntityCoords(targetPed)) <= 4.0 then
                    ClearPedTasks(kidPed)
                    Wait(50)

                    SetEntityAsMissionEntity(kidPed, true, true)
                    SetEntityAsMissionEntity(targetPed, true, true)

                    Citizen.InvokeNative(0x18FF3110CF47115D, targetPed, 2, true)
                    Citizen.InvokeNative(0x18FF3110CF47115D, targetPed, 7, true)
                    Citizen.InvokeNative(0x18FF3110CF47115D, targetPed, 12, true)
                    Citizen.InvokeNative(0x18FF3110CF47115D, targetPed, 17, true)

                    local carryConfig = Citizen.InvokeNative(0x34F008A7E48C496B, targetPed, 0)
                    if not carryConfig or carryConfig == 0 then
                        carryConfig = GetHashKey('CARRY_HUMAN_CORPSE')
                    end

                    Citizen.InvokeNative(0xF0B4F759F35CC7F5, targetPed, carryConfig, kidPed, 3, 0)
                    Citizen.InvokeNative(0x502EC17B1BED4BFA, kidPed, targetPed)

                    local carryTimeout = GetGameTimer() + 8000
                    local isCarrying = false
                    while GetGameTimer() < carryTimeout do
                        Wait(300)
                        local isCarryingNative = Citizen.InvokeNative(0xA911EE21EDF69DAF, kidPed)
                        local carried = Citizen.InvokeNative(0x6B67320E0D57856A, kidPed, Citizen.PointerValueInt(), 2, false)
                        if isCarryingNative or carried == targetPed or IsEntityAttachedToEntity(targetPed, kidPed) then
                            isCarrying = true
                            break
                        end
                    end

                    if isCarrying then
                        Wait(1500)
                    else
                        if DoesEntityExist(targetPed) then
                            RequestAnimDict('mech_carry_box')
                            local animTimeout = GetGameTimer() + 3000
                            while not HasAnimDictLoaded('mech_carry_box') do
                                Wait(10)
                                if GetGameTimer() > animTimeout then break end
                            end

                            if HasAnimDictLoaded('mech_carry_box') then
                                TaskPlayAnim(kidPed, 'mech_carry_box', 'pickup',
                                    4.0, -4.0, 1800, 0, 0, false, 0, false, 0, false)
                                Wait(900)
                            end

                            local spinebone = GetEntityBoneIndexByName(kidPed, 'SKEL_L_Clavicle')
                            if spinebone == -1 then spinebone = GetEntityBoneIndexByName(kidPed, 'SPINE_ROOT') end
                            if spinebone == -1 then spinebone = GetPedBoneIndex(kidPed, 0) end

                            AttachEntityToEntity(targetPed, kidPed, spinebone,
                                0.0, 0.2, 0.1,
                                0.0, 90.0, 90.0,
                                false, false, false, false, 2, true, false, false)

                            Wait(900)

                            if HasAnimDictLoaded('mech_carry_box') then
                                TaskPlayAnim(kidPed, 'mech_carry_box', 'idle',
                                    8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
                            end
                        end
                    end

                    TaskGoToCoordAnyMeans(kidPed, Config.DropCoords.x, Config.DropCoords.y, Config.DropCoords.z, 1.0, 0, 0, 786603, 0xbf800000)
                    local timeout = GetGameTimer() + 60000
                    while #(GetEntityCoords(kidPed) - vec3(Config.DropCoords.x, Config.DropCoords.y, Config.DropCoords.z)) > 2.5 do
                        Wait(500)
                        if GetGameTimer() > timeout then break end
                    end

                    ClearPedTasks(kidPed)
                    Wait(50)

                    Citizen.InvokeNative(0xC7F0B43DCDC57E3D, kidPed, targetPed, Config.DropCoords.x, Config.DropCoords.y, Config.DropCoords.z, Config.DropCoords.w or 0.0, 0)

                    local dropTimeout = GetGameTimer() + 5000
                    while GetGameTimer() < dropTimeout do
                        Wait(300)
                        local isStillCarrying = Citizen.InvokeNative(0xA911EE21EDF69DAF, kidPed)
                        if not isStillCarrying then
                            break
                        end
                    end

                    Wait(1000)

                    if IsEntityAttachedToEntity(targetPed, kidPed) then
                        DetachEntity(targetPed, true, false)
                    end

                    ClearPedTasks(kidPed)
                end
            end

            TriggerServerEvent('torp_orderly:server:pedCleaned', targetNetId)

            if DoesEntityExist(kidPed) then
                TaskGoToCoordAnyMeans(kidPed, Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z, 1.0, 0, 0, 786603, 0xbf800000)
                local timeout2 = GetGameTimer() + 60000
                while #(GetEntityCoords(kidPed) - vec3(Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z)) > 2.0 do
                    Wait(500)
                    if GetGameTimer() > timeout2 then break end
                end

                ClearPedTasks(kidPed)
                SetEntityCoords(kidPed, Config.SpawnCoords.x, Config.SpawnCoords.y, Config.SpawnCoords.z - 1.0, false, false, false, false)
                SetEntityHeading(kidPed, Config.SpawnCoords.w)
                FreezeEntityPosition(kidPed, true)
            end

            isBusy = false
        end
        ::continue::
    end
end)

local isRevivingNPC = false

local function playBandageAnim(ped)
    local dict = "mini_games@story@mob4@heal_jules@bandage@arthur"
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do
        Wait(10)
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, "bandage_start", 1.0, 8.0, -1, 1, 0, false, false, false)
    else
        TaskStartScenarioInPlace(ped, `WORLD_HUMAN_CROUCH_INSPECT`, -1, true, false, false, false)
    end
end

local function isDoctorPlayer()
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    local jobName = PlayerData.job.name
    local jobType = PlayerData.job.type
    if not jobName and not jobType then return false end

    for _, j in ipairs(Config.DoctorJobs) do
        if jobName == j or jobType == j or (jobName and jobName:find(j)) or (jobType and jobType:find(j)) then
            return true
        end
    end
    return false
end

RegisterNetEvent('torp_orderly:client:revivePed', function(entity)
    if isRevivingNPC then return end
    if not DoesEntityExist(entity) or not IsEntityDead(entity) then return end

    local playerPed = PlayerPedId()
    isRevivingNPC = true

    TaskTurnPedToFaceEntity(playerPed, entity, 1000)
    Wait(1000)

    FreezeEntityPosition(playerPed, true)
    playBandageAnim(playerPed)

    if Config.MeCommandText and Config.MeCommandText ~= '' then
        ExecuteCommand('me ' .. Config.MeCommandText)
    end

    local duration = Config.ReviveDuration or 15000
    local success = false

    if lib and lib.progressBar then
        success = lib.progressBar({
            duration = duration,
            label = Config.ProgressLabel,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disableControl = true,
            disable = {
                move = true,
                mouse = false,
            }
        })
    elseif RSGCore and RSGCore.Functions and RSGCore.Functions.Progressbar then
        local finished = false
        RSGCore.Functions.Progressbar("revive_patient", Config.ProgressLabel, duration, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            finished = true
        end, function()
            finished = false
        end)

        local t = GetGameTimer() + duration + 500
        while GetGameTimer() < t and not finished do
            Wait(100)
        end
        success = finished
    else
        local startTime = GetGameTimer()
        local endTime = startTime + duration
        while GetGameTimer() < endTime do
            Wait(0)
            local pct = math.floor(((GetGameTimer() - startTime) / duration) * 100)
            SetTextScale(0.35, 0.35)
            SetTextColor(255, 255, 255, 220)
            SetTextCentre(true)
            SetTextDropshadow(1, 0, 0, 0, 255)
            local str = CreateVarString(10, "LITERAL_STRING", Config.ProgressLabel .. ": " .. tostring(pct) .. "%")
            DisplayText(str, 0.5, 0.85)
        end
        success = true
    end

    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)

    if success and DoesEntityExist(entity) then
        ResurrectPed(entity)
        Citizen.InvokeNative(0x8D8812D33D35B574, entity)
        ClearPedTasksImmediately(entity)
        SetEntityHealth(entity, GetEntityMaxHealth(entity))
        ClearPedBloodDamage(entity)
        SetPedCanRagdoll(entity, true)

        SetPedKeepTask(entity, true)
        SetBlockingOfNonTemporaryEvents(entity, false)
        Wait(1000)

        TaskSmartFleePed(entity, playerPed, Config.FleeDistance or 120.0, -1, 3, 1.2, 0)
        SetPedAsNoLongerNeeded(entity)

        local netId = PedToNet(entity)
        if netId ~= 0 then
            TriggerServerEvent('torp_orderly:server:pedCleaned', netId)
        end

        if lib and lib.notify then
            lib.notify({ title = 'Paciente Atendido', description = Config.NotifySuccess, type = 'success' })
        elseif RSGCore and RSGCore.Functions and RSGCore.Functions.Notify then
            RSGCore.Functions.Notify(Config.NotifySuccess, 'success')
        end
    else
        if lib and lib.notify then
            lib.notify({ title = 'Cancelado', description = Config.NotifyCancel, type = 'error' })
        end
    end

    isRevivingNPC = false
end)

CreateThread(function()
    Wait(2000)

    local globalOptions = {
        {
            name = 'torp_orderly_revive_global',
            icon = Config.Target.Icon,
            label = Config.Target.Label,
            onSelect = function(data)
                local ent = data and data.entity
                if ent and DoesEntityExist(ent) then
                    TriggerEvent('torp_orderly:client:revivePed', ent)
                end
            end,
            action = function(entity)
                if entity and DoesEntityExist(entity) then
                    TriggerEvent('torp_orderly:client:revivePed', entity)
                end
            end,
            canInteract = function(entity)
                if not DoesEntityExist(entity) or not IsEntityDead(entity) then return false end
                if GetEntityModel(entity) == Config.KidModel then return false end
                return isDoctorPlayer()
            end,
            distance = Config.Target.Distance
        }
    }

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addGlobalPed(globalOptions)
    elseif GetResourceState('rsg-target') == 'started' then
        exports['rsg-target']:AddGlobalPed({
            options = globalOptions,
            distance = Config.Target.Distance
        })
    end
end)
