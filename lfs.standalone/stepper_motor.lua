
-- Stepper control control_schemes
-- See http://users.ece.utexas.edu/~valvano/Datasheets/Stepper_ST.pdf

-- Rotating wave: 
--  ENA = ENB = 1 always
--       ____                _
--   A _|    |____.____.____| 
--            ____
--   B _.____|    |____.____._
--                 ____
--  #A _.____.____|    |____._
--                      ____
--  #B _.____.____.____|    |_
--
--      |<-0-|--1-|--2-|--3>|
--
-- Full step:
--  ENA = ENB = 1 always, #A = not A, #B = not B
--       _________           _
--   A _|         |____.____| 
--            _________
--   B _.____|         |____._
--     _           _________
--  #A  |____.____|         |_
--     _.____           ____._
--  #B       |____.____|      
--
--      |<-0-|--1-|--2-|--3>|
--
-- Half step always-on:
--  ENA = ENB = 1 always
--       ______________                          _
--   A _|              |____.____.____.____.____|
--                 ______________
--   B _.____.____|              |____.____.____._
--                           ______________
--  #A _.____.____.____.____|              |____._
--     _.____                          ____.____._
--  #B       |____.____.____.____.____|         
--
--      |<-0-|--1-|--2-|--3-|--4-|--5-|--6-|--7>|
--
-- Half step with inhibition
--  #A = not A, #B = not B, NOTE: different order of signals!
--       ____.____.____.____                     _
--   A _|                  \|____.____.____.___/|
--       ____.____.____      ____.____.____      _
-- EnA _|              |____|              |____|
--     _                     ____.____.____.____
--  #A  |____.____.____.___/|                  \|_
--
--                 ____.____.____.____
--   B _.____.___/|                  \|____.____._
--     _.____      ____.____.____      ____.____._
-- EnB       |____|              |____|          
--     _.____.____                     ____.____._
--  #B           \|____.____.____.___/|          
--
--      |<-0-|--1-|--2-|--3-|--4-|--5-|--6-|--7>|
--
-- Bit encoding:
-- bit 0 = A pos
-- bit 1 = A neg
-- bit 2 = A ena
-- bit 3 = N/A
-- bit 4 = B pos
-- bit 5 = B neg
-- bit 6 = B ena
-- bit 7 = N/A

schemes = {
    wave =              { 0x45, 0x54, 0x46, 0x64 },
    fullstep =          { 0x65, 0x55, 0x46, 0x66 },
    halfstep =          { 0x65, 0x45, 0x55, 0x54, 0x56, 0x46, 0x66, 0x64 },
    halfstep_w_ena =    { 0x65, 0x25, 0x55, 0x51, 0x56, 0x16, 0x66, 0x62 },
}

local function new_stepper_motor(pinout)
    local self = {
        speed = 6,
        position = 0,
        keep_locked = false,
        scheme_name = "halfstep_w_ena"
    }

    local scheme = schemes[self.scheme_name]
    local wanted_pos = 0
    local lock_when_done = false

    local scheme = schemes.halfstep_w_ena
    local current_phase = 1
    
    -- Set the pins as output
    for k, v in pairs(pinout) do
        gpio.mode(v, gpio.OUTPUT)
    end

    local function set_state(n)
        --print("Set state; val='" .. n .. "'")
        -- For reducing transitional hazards:
        --   If an Ena pin falls, set that first
        --   If it rises, set that last
        if pinout.B_ena and bit.band(n, 0x40) == 0 then
            gpio.write(pinout.B_ena, 0)
        end
        if pinout.A_ena and bit.band(n, 0x04) == 0 then
            gpio.write(pinout.A_ena, 0)
        end

        if pinout.A_pos then
            gpio.write(pinout.A_pos, bit.band(n, 0x01) == 0 and 0 or 1)
        end
        if pinout.A_neg then
            gpio.write(pinout.A_neg, bit.band(n, 0x02) == 0 and 0 or 1)
        end

        if pinout.B_pos then
            gpio.write(pinout.B_pos, bit.band(n, 0x10) == 0 and 0 or 1)
        end
        if pinout.B_neg then
            gpio.write(pinout.B_neg, bit.band(n, 0x20) == 0 and 0 or 1)
        end

        if pinout.B_ena and bit.band(n, 0x40) ~= 0 then
            gpio.write(pinout.B_ena, 1)
        end
        if pinout.A_ena and bit.band(n, 0x04) ~= 0 then
            gpio.write(pinout.A_ena, 1)
        end
    end

    local t = tmr.create()

    local function timer_event(timer)
        -- print("Timer; position='" .. self.position .. "/" .. wanted_pos .. "', current_phase='" .. current_phase .."/" .. #scheme .. "'")
        if wanted_pos < self.position then
            current_phase = current_phase == 1 and #scheme or current_phase - 1
            self.position = self.position - 1
            set_state(scheme[current_phase])
        elseif wanted_pos > self.position then
            current_phase = current_phase == #scheme and 1 or current_phase + 1
            self.position = self.position + 1
            set_state(scheme[current_phase])
        else
            -- needed for the case when we won't move it, just change the lockedness
            t:stop()
            current_phase = 1
            set_state(lock_when_done and phases[current_phase] or 0)
        end
    end

    t:register(self.speed, tmr.ALARM_AUTO, timer_event)

    self.step_to = function (pos, lock)
        print("Step to; pos='" .. pos .. "'")
        wanted_pos = pos
        lock_when_done = self.keep_locked
        t:start()
    end

    self.step_by = function (pos, lock)
        print("Step by; pos='" .. pos .. "'")
        wanted_pos = self.position + pos
        lock_when_done = self.keep_locked
        t:start()
    end

    self.set_speed = function (spd)
        self.speed = spd
        t:interval(spd)
    end

    self.set_scheme = function (name)
        if schemes[name] then
            self.scheme_name = name
            scheme = schemes[self.scheme_name]
            current_phase = 1
            return true
        end
        return false
    end

    self.set_lock_policy = function (lck)
        self.keep_locked = lck
    end

    self.release = function ()
        t:stop()
        current_phase = 1
        set_state(0)
    end

    return self
end

return {
    schemes = schemes,
    new = new_stepper_motor,
}
-- vim: set sw=4 ts=4 et:
