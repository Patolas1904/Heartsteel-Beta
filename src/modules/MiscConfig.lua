return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    Misc.ANTI_AFK_DELAY     = 20
    Misc.SIM_MOVE_DELAY     = 20
    Misc.SIM_MOVE_DISTANCE  = 1.5
    Misc.SIM_MOVE_WAIT      = 0.12

    Misc.ELEMENT_OPTIONS = {"Fire","Water","Earth","Plasma"}
end
