-- ============================================================
-- FS25_BoggingHUD.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

BoggingHUD = {modDirectory=g_currentModDirectory}

function BoggingHUD.hasSlip(vehicle)
    local spec = vehicle.spec_wheels
    if spec == nil then return false end
    local speed = math.abs(vehicle:getLastSpeed()) / 3.6
    for _, wheel in ipairs(spec.wheels) do
        local p = wheel.physics
        local contact = p ~= nil and ((vehicle.isServer and p.hasGroundContact)
            or (not vehicle.isServer and p.contact ~= nil and p.contact ~= WheelContactType.NONE))
        if contact then
            if p.rbSoil ~= nil and p.rbSoil.depth >= 0.28 then return true end
            local rotation = math.abs((p.netInfo and p.netInfo.xDriveSpeed) or 0) * (p.radius or 0)
            local slip = (rotation - speed) / math.max(rotation, 0.5)
            if rotation > 0.8 and slip > 0.35 then return true end
        end
    end
    return false
end

function BoggingHUD.slotOccupied(vehicle)
    local env = _G.FS25_AdvancedVehicleFunctions
    local control = (env and env.g_VehicleSystems) or _G.g_VehicleSystems
    local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or vehicle
    if control ~= nil and control.getVehicleRoot ~= nil then root = control:getVehicleRoot(vehicle) end
    if root ~= nil and root.frcHandbrakeActive == true then return true end
    return control ~= nil and control.preheatRootVehicle == root and (control.preheatRemaining or 0) > 0
end

function BoggingHUD.draw(speedMeter)
    local self = BoggingHUD
    local vehicle = speedMeter.vehicle
    if self.overlay == nil or vehicle == nil or not speedMeter.isVehicleDrawSafe
        or speedMeter.speedBg == nil or vehicle.spec_motorized == nil then return end
    local now = g_time or 0
    if self.vehicle ~= vehicle then
        self.vehicle, self.since, self.lastSlip = vehicle, nil, nil
    end
    if self.hasSlip(vehicle) then
        self.since = self.since or now
        self.lastSlip = now
    elseif self.lastSlip == nil or now - self.lastSlip > 500 then
        self.since, self.lastSlip = nil, nil
    end
    if self.since == nil or now - self.since < 250 or self.slotOccupied(vehicle)
        or math.floor(now / 300) % 2 == 1 then return end
    local x, y = speedMeter:getPosition()
    local w, h = speedMeter:scalePixelValuesToScreenVector(26, 26)
    local gap, offset = speedMeter:scalePixelValuesToScreenVector(6, 2)
    self.overlay:setDimension(w, h)
    self.overlay:setPosition(x + speedMeter.aiIconOffsetX - w - gap,
        y + speedMeter.aiIconOffsetY + offset)
    self.overlay:setColor(1, 1, 1, 1)
    self.overlay:render()
end

function BoggingHUD:loadMap()
    if g_dedicatedServer ~= nil then return end
    self.overlay = Overlay.new(self.modDirectory .. "icons/wheelSlip.dds", 0, 0, 0, 0)
    if not self.installed then
        SpeedMeterDisplay.draw = Utils.appendedFunction(SpeedMeterDisplay.draw, BoggingHUD.draw)
        self.installed = true
    end
end

function BoggingHUD:deleteMap()
    if self.overlay ~= nil then self.overlay:delete(); self.overlay = nil end
    self.vehicle, self.since, self.lastSlip = nil, nil, nil
end

addModEventListener(BoggingHUD)
