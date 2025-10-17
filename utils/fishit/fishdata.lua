local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function SerializeValue(v, indent)
    local spacing = string.rep("\t", indent)
    
    if type(v) == "table" then
        if next(v) == nil then
            return "{}"
        end
        
        local result = "{\n"
        local keys = {}
        for k in pairs(v) do
            table.insert(keys, k)
        end
        
        for i, k in ipairs(keys) do
            result = result .. spacing .. "\t" .. k .. " = " .. SerializeValue(v[k], indent + 1)
            if i < #keys then
                result = result .. ";"
            else
                result = result .. ";"
            end
            result = result .. "\n"
        end
        
        result = result .. spacing .. "}"
        return result
    elseif type(v) == "string" then
        return '"' .. v .. '"'
    elseif type(v) == "number" then
        return tostring(v)
    elseif type(v) == "boolean" then
        return tostring(v)
    else
        return tostring(v)
    end
end

local function ExtractFishData()
    local output = "return {\n"
    local itemsFolder = ReplicatedStorage:FindFirstChild("Items")
    
    if not itemsFolder then
        warn("Items folder not found!")
        return
    end
    
    local fishData = {}
    
    for _, item in pairs(itemsFolder:GetDescendants()) do
        if item:IsA("ModuleScript") then
            local success, data = pcall(function()
                return require(item)
            end)
            
            if success and data and data.Data and data.Data.Type == "Fishes" then
                table.insert(fishData, {module = item, data = data})
            end
        end
    end
    
    if #fishData == 0 then
        warn("No fish data found!")
        return
    end
    
    table.sort(fishData, function(a, b)
        return a.data.Data.Id < b.data.Data.Id
    end)
    
    for i, fish in ipairs(fishData) do
        local data = fish.data
        output = output .. '\t["' .. fish.module.Name .. '"] = {\n'
        output = output .. '\t\tData = {\n'
        output = output .. '\t\t\tId = ' .. data.Data.Id .. ';\n'
        output = output .. '\t\t\tType = "' .. data.Data.Type .. '";\n'
        output = output .. '\t\t\tName = "' .. data.Data.Name .. '";\n'
        output = output .. '\t\t\tDescription = "' .. data.Data.Description .. '";\n'
        output = output .. '\t\t\tIcon = "' .. data.Data.Icon .. '";\n'
        output = output .. '\t\t\tTier = ' .. data.Data.Tier .. ';\n'
        output = output .. '\t\t};\n'
        output = output .. '\t\tSellPrice = ' .. data.SellPrice .. ';\n'
        output = output .. '\t\tVariants = {};\n'
        output = output .. '\t\tWeight = {\n'
        output = output .. '\t\t\tBig = NumberRange.new(' .. data.Weight.Big.Min .. ', ' .. data.Weight.Big.Max .. ');\n'
        output = output .. '\t\t\tDefault = NumberRange.new(' .. data.Weight.Default.Min .. ', ' .. data.Weight.Default.Max .. ');\n'
        output = output .. '\t\t};\n'
        output = output .. '\t\tProbability = {\n'
        output = output .. '\t\t\tChance = ' .. data.Probability.Chance .. ';\n'
        output = output .. '\t\t};\n'
        output = output .. '\t}' .. (i < #fishData and ';\n' or ';\n')
    end
    
    output = output .. '}'
    
    if writefile then
        writefile("FishData.lua", output)
        print("✓ Saved "..#fishData.." fishes to FishData.lua")
    else
        if setclipboard then
            setclipboard(output)
            print("✓ Copied "..#fishData.." fishes to clipboard")
        else
            print(output)
        end
    end
end

ExtractFishData()