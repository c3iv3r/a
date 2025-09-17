-- Memuat daftar game dari GitHub
local ok, gamesOrErr = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/games.lua"))()
end)
if not ok then
    warn("[dev] gagal memuat daftar game:", gamesOrErr)
    return
end

local Games = gamesOrErr

-- Ambil URL berdasarkan PlaceId (atau Anda bisa ganti dengan game.GameId jika diperlukan)
local url = Games[game.PlaceId]
if not url then
    warn("[dev] Game belum didukung. PlaceId: "..tostring(game.PlaceId))
    return
end

-- Ambil sumber script dari URL
local scriptSource = game:HttpGet(url)
if not scriptSource then
    warn("[dev] Tidak bisa mengambil script dari "..url)
    return
end

-- Compile scriptnya
local fn, err = loadstring(scriptSource)
if not fn then
    warn("[dev] loadstring gagal: "..tostring(err))
    return
end

-- Jalankan script jika semuanya sukses
fn()
