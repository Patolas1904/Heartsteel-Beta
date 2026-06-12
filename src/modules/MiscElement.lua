return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    function Misc.applyElement(selectedValue)
        Core.UIActionRemote:FireServer("ChangeElement", selectedValue or Core.selectionState.selected_element)
    end
end
