-- ============================================================
-- FS25_BoggingModel.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

BoggingModel = {}

local function clamp(x, a, b)
    return math.max(a, math.min(b, x))
end

function BoggingModel.terminal(depth)
    local t = clamp((depth - 0.28) / 0.47, 0, 1)
    return t * t * (3 - 2 * t)
end

function BoggingModel.wetGrip(wetness, grass, field)
    local wet = clamp((wetness - 0.20) / 0.80, 0, 1)
    wet = wet * wet * (3 - 2 * wet)
    local loss = grass and 0.16 or (field and 0.14 or 0.10)
    local lateralLoss = grass and 0.20 or 0.14
    return 1 - loss * wet, 1 - lateralLoss * wet
end

function BoggingModel.step(depth, dt, wetness, softness, load, width, radius, crawler, speed, wheelSpeed, driveDemand)
    if wetness <= 0.20 then return 0, 1, 0, 0, 0 end

    dt = clamp(dt, 0, 0.1)
    driveDemand = clamp(math.abs(driveDemand or 0), 0, 1)

    local area = math.max(0.04, width * radius * (crawler and 1.8 or 0.55))
    local pressure = math.max(0, load) * 9.81 / area

    local wet = clamp((wetness - 0.20) / 0.80, 0, 1)
    wet = wet * wet * (3 - 2 * wet)
    local risk = clamp(wet * softness * pressure / 78, 0, 1.8)

    speed, wheelSpeed = math.abs(speed), math.abs(wheelSpeed)

    local slip = clamp((wheelSpeed - speed - 0.10) / math.max(wheelSpeed, 0.45), 0, 1)

    local lowSpeed = 1 - clamp(speed / 3.0, 0, 1)
    local demandShear = driveDemand * lowSpeed * 0.68
    local shear = clamp(math.max(slip, demandShear), 0, 1)

    local rolling = clamp(math.max(speed, wheelSpeed) / 0.45, 0, 1)
    local working = math.max(rolling, driveDemand * lowSpeed * 0.45)

    local digging = risk * (0.008 * rolling + 0.080 * shear * shear) * working

    local escape = speed * 0.22 * (1 - shear)^3
    local drying = (1 - wet) * 0.0015

    depth = clamp(depth + (digging - depth * (escape + drying)) * dt, 0, 1)

    local resistance = clamp(risk * 0.055 + depth * depth * 0.82, 0, 0.86)
    local grip = clamp(1 - risk * 0.13 - depth * 0.65, 0.18, 1)

    return depth, grip, math.max(load, 0) * 9.81 * radius * resistance, risk, shear
end

function BoggingModel.dragForce(torqueEquivalent, radius, massShare, speed, dt)
    if dt <= 0 or radius <= 0 or speed <= 0 then return 0 end
    return math.min(math.max(0, torqueEquivalent / radius),
        math.max(0, massShare) * speed / dt * 0.5)
end
