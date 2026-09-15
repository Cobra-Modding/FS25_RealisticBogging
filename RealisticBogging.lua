-- ============================================================
-- FS25_RealisticBogging.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

RealisticBogging = {}

function RealisticBogging.captureDriveDemand(self, superFunc, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
    local requested = acceleration or 0
    if math.abs(currentSpeed or 0) > 0.0003 and requested * currentSpeed < 0 then
        requested = 0
    end
    self.rbRequestedDriveDemand = math.max(0, math.min(1, math.abs(requested)))
    self.rbRequestedDriveDemandTime = g_time or 0
    return superFunc(self, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
end

function RealisticBogging.clear(wheel)
    local state = wheel.rbSoil
    if state ~= nil and state.grip ~= 1 then
        wheel.isFrictionDirty = true
    end
    wheel.rbSoil = nil
end

function RealisticBogging.updateWetGrip(self, groundWetness)
    local grip, lateral = 1, 1
    if self.vehicle.isAddedToPhysics and self.hasGroundContact and not self.hasSnowContact
        and (self.contact == WheelContactType.GROUND or self.contact == WheelContactType.OBJECT) then
        local ground = self.densityType
        local field = self.contact == WheelContactType.GROUND and ground ~= nil and ground ~= FieldGroundType.NONE
        local grass = field and (ground == FieldGroundType.GRASS or ground == FieldGroundType.GRASS_CUT)
        grip, lateral = BoggingModel.wetGrip(groundWetness or 0, grass, field)
    end
    if grip ~= (self.rbWetGrip or 1) or lateral ~= (self.rbWetLateral or 1) then
        self.isFrictionDirty = true
    end
    self.rbWetGrip, self.rbWetLateral = grip, lateral
end

function RealisticBogging.updateSoil(self, dt, groundWetness)
    if not self.vehicle.isServer then return end
    RealisticBogging.updateWetGrip(self, groundWetness)
    if not self.vehicle.isAddedToPhysics or not self.hasGroundContact
        or self.contact ~= WheelContactType.GROUND or self.hasSnowContact
        or self.densityType == nil or self.densityType == FieldGroundType.NONE then
        RealisticBogging.clear(self)
        return
    end
    local load = self:getTireLoad()
    if load == nil or load <= 0 or self.radius == nil or self.radius <= 0 then
        RealisticBogging.clear(self)
        return
    end
    local state = self.rbSoil
    if state == nil then
        state = {depth=0, grip=1, drag=0, driveDemand=0, shear=0}
        self.rbSoil = state
    end
    local x, z = self.lastContactX, self.lastContactZ
    if x ~= nil and z ~= nil and state.x ~= nil
        and (x-state.x)^2 + (z-state.z)^2 > 100 then
        state.depth = 0 
    end
    state.x, state.z = x, z
    local softness = 0.8
    local ground = self.densityType
    if ground == FieldGroundType.GRASS or ground == FieldGroundType.GRASS_CUT then
        softness = 0.42
    elseif ground == FieldGroundType.PLOWED then
        softness = 1.25
    elseif ground == FieldGroundType.CULTIVATED then
        softness = 1.05
    end
    local width = self.width or 0.5
    if self.wheel.visualWheels ~= nil then
        local sum = 0
        for _, visual in ipairs(self.wheel.visualWheels) do
            if visual.getWidthAndOffset ~= nil then
                local w = visual:getWidthAndOffset()
                sum = sum + math.max(0, w or 0)
            end
        end
        width = math.max(width, sum)
    end
    local crawler = WheelsUtil.getTireTypeName(self.tireType) == "CRAWLER"
    local wetness = math.max(0, math.min(1, groundWetness or 0))
    if self.hasWaterContact then wetness = 1 end
    local speed = self.vehicle:getLastSpeed() / 3.6
    local wheelSpeed = math.abs((self.netInfo and self.netInfo.xDriveSpeed) or 0) * self.radius

    local driveDemand = 0
    local demandAge = (g_time or 0) - (self.vehicle.rbRequestedDriveDemandTime or -100000)
    if demandAge >= 0 and demandAge <= 250 then
        driveDemand = self.vehicle.rbRequestedDriveDemand or 0
    end
    local motorized = self.vehicle.spec_motorized
    if motorized ~= nil and motorized.lastControlParameters ~= nil then
        driveDemand = math.max(driveDemand, math.abs(motorized.lastControlParameters.acceleratorPedal or 0))
    end
    driveDemand = math.max(0, math.min(1, driveDemand))

    local oldDemand = state.driveDemand or 0
    if driveDemand >= oldDemand then
        state.driveDemand = driveDemand
    else
        state.driveDemand = math.max(driveDemand, oldDemand - dt / 450)
    end

    state.wetness, state.load, state.wheelSpeed = wetness, load, wheelSpeed
    local oldGrip = state.grip
    state.depth, state.grip, state.drag, state.risk, state.shear = BoggingModel.step(
        state.depth, dt/1000, wetness, softness, load, width, self.radius, crawler,
        speed, wheelSpeed, state.driveDemand)
    if math.abs(state.grip - oldGrip) > 0.000001 then
        self.isFrictionDirty = true
    end
end

function RealisticBogging.applyFriction(self, superFunc, ...)
    local original = self.frictionScale
    local originalLong = self.maxLongStiffness
    local originalLat = self.maxLatStiffness
    if self.vehicle.isServer then
        local soilGrip = self.rbSoil ~= nil and self.rbSoil.grip or 1
        self.frictionScale = original * math.min(soilGrip, self.rbWetGrip or 1)
        if originalLat ~= nil then self.maxLatStiffness = originalLat * (self.rbWetLateral or 1) end
        if self.rbSoil ~= nil then
            local terminal = BoggingModel.terminal(self.rbSoil.depth)
            self.maxLongStiffness = originalLong * (1 - 0.9999 * terminal)
        end
    end
    superFunc(self, ...)
    self.frictionScale = original
    self.maxLongStiffness = originalLong
    self.maxLatStiffness = originalLat
end

function RealisticBogging.updateBogSink(self, dt)
    if not self.vehicle.isServer then return end
    local old = self.rbSink or 0
    local target = 0
    if self.rbSoil ~= nil then
        target = math.min(0.20, self.radius * 0.25) * BoggingModel.terminal(self.rbSoil.depth)
    end
    local step = math.min(math.max(dt / 1000, 0), 0.1) * 0.025
    local sink = old + math.max(-step, math.min(step, target - old))
    self.rbSink = sink
    if math.abs(sink - (self.rbAppliedSink or 0)) > 0.001
        or (sink == 0 and (self.rbAppliedSink or 0) ~= 0) then
        self.isPositionDirty = true
    end
end

function RealisticBogging.applySinkShape(self, superFunc, ...)
    local original = self.radius
    if self.vehicle.isServer then
        self.radius = math.max(original * 0.75, original - (self.rbSink or 0))
    end
    superFunc(self, ...)
    self.radius = original
    if self.vehicle.isServer and self.vehicle.isAddedToPhysics then
        self.rbAppliedSink = self.rbSink or 0
    end
end

function RealisticBogging.applyBodyResistance(self, dt)
    local state = self.rbSoil
    if not self.vehicle.isServer or not self.vehicle.isAddedToPhysics
        or state == nil or state.drag <= 0 or dt <= 0 then return end
    local node = self.wheel.node
    local vx, _, vz = getLinearVelocity(node)
    local speed = math.sqrt(vx * vx + vz * vz)
    if speed < 0.00001 then return end
    local count = 0
    local spec = self.vehicle.spec_wheels
    if spec ~= nil then
        for _, wheel in ipairs(spec.wheels) do
            if wheel.node == node then count = count + 1 end
        end
    end
    local massShare = getMass(node) / math.max(count, 1)
    local force = BoggingModel.dragForce(state.drag, self.radius, massShare, speed, dt / 1000)
    local px, py, pz = getCenterOfMass(node)
    addForce(node, -vx / speed * force, 0, -vz / speed * force, px, py, pz, true)
end

function RealisticBogging:loadMap()
    if self.installed then return end
    if WheelPhysics == nil or WheelPhysics.updateFriction == nil
        or WheelPhysics.updateTireFriction == nil or WheelPhysics.updatePhysics == nil
        or WheelPhysics.serverUpdate == nil or WheelPhysics.updateBase == nil
        or WheelsUtil == nil or WheelsUtil.updateWheelsPhysics == nil then
        Logging.error("[RealisticBogging] Unsupported WheelPhysics API; mod disabled")
        return
    end
    WheelsUtil.updateWheelsPhysics = Utils.overwrittenFunction(
        WheelsUtil.updateWheelsPhysics, RealisticBogging.captureDriveDemand)
    WheelPhysics.updateFriction = Utils.appendedFunction(WheelPhysics.updateFriction, RealisticBogging.updateSoil)
    WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, RealisticBogging.applyFriction)
    WheelPhysics.serverUpdate = Utils.appendedFunction(WheelPhysics.serverUpdate, RealisticBogging.updateBogSink)
    WheelPhysics.serverUpdate = Utils.appendedFunction(WheelPhysics.serverUpdate, RealisticBogging.applyBodyResistance)
    WheelPhysics.updateBase = Utils.overwrittenFunction(WheelPhysics.updateBase, RealisticBogging.applySinkShape)
    self.installed = true
    Logging.info("[RealisticBogging] 1.0.0.0 loaded. Progressive bogging and ASR-compatible soil shear enabled.")
end

addModEventListener(RealisticBogging)
