-- ===== games.lua (resolver function) =====

local URLs = {
    ["121864768012064"] = "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2MzaXYzci9hL3JlZnMvaGVhZHMvbWFpbi9wdWIvZmlzaGl0Lmx1YQ==", -- GUI utama (Base64)
    -- Tambahkan mapping lain di sini
}

-- Base64 decode (whitespace-safe)
local function b64decode(s)
    s = (s:gsub("%s+", "")) -- hapus whitespace
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    s=s:gsub('[^'..b..'=]','')
    return (s:gsub('.', function(x)
        if x=='=' then return '' end
        local r,f='', (b:find(x)-1)
        for i=6,1,-1 do r = r .. ((f % 2^i - f % 2^(i-1) > 0) and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x < 8 then return '' end
        local c=0
        for i=1,8 do c = c + ((x:sub(i,i)=='1') and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

return function(placeId)
    local enc = URLs[placeId]
    if not enc then return nil end
    return b64decode(enc)
end