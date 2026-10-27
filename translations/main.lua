local json = require("json")

Mizuki.Translations = {
    en = include("translations/en"),
    zh = include("translations/zh"),
}

local function normalizeLanguage(language)
    if language == "zh_cn" then return "zh" end
    if language == "en_us" then return "en" end
    return Mizuki.Translations[language] and language or "en"
end

local function readSettingsRoot()
    if not Mizuki:HasData() then return {} end
    local ok, root = pcall(json.decode, Mizuki:LoadData())
    return ok and type(root) == "table" and root or {}
end

local saved = readSettingsRoot().Settings
local selectedLanguage = type(saved) == "table" and saved.Language
if selectedLanguage ~= "en" and selectedLanguage ~= "zh" then
    selectedLanguage = "zh"
end

function Mizuki.GetLanguage()
    if REPENTANCE_PLUS then return selectedLanguage end
    return normalizeLanguage(Options.Language)
end

-- Explicit language requests, including EID's language, remain independent.
function Mizuki.GetTranslation(language)
    return Mizuki.Translations[normalizeLanguage(language or Mizuki.GetLanguage())]
end

local nativeXmlStatus = "idle"
local nativeXmlRequiresRestart = false
local nativeXmlPending = false
local nativeXmlNextAttempt = 0
local scriptSource = debug and debug.getinfo and debug.getinfo(1, "S").source
local modDirectory = scriptSource and scriptSource:gsub("\\", "/")
    :match("^@(.*/)translations/main%.lua$")

local function xmlText(text)
    return text:gsub("&", "&amp;"):gsub('"', "&quot;")
        :gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function replaceAttributes(source, tag, identity, values)
    local matched = 0
    local result = source:gsub("<" .. tag .. "%s[^>]-/>", function(entry)
        if not entry:find(identity, 1, true) then return entry end
        matched = matched + 1
        for attribute, value in pairs(values) do
            local count
            entry, count = entry:gsub(attribute .. '="[^"]*"', function()
                return attribute .. '="' .. xmlText(value) .. '"'
            end)
            assert(count == 1, "Missing XML attribute: " .. attribute)
        end
        return entry
    end)
    assert(matched == 1, "Missing or duplicate XML item: " .. identity)
    return result
end

local function replaceNativeXml()
    local translation = Mizuki.GetTranslation()
    local files = {}
    for _, name in ipairs({"items", "pocketitems", "info_display"}) do
        local path = modDirectory .. "content/" .. name .. ".xml"
        local file = assert(io.open(path, "rb"))
        local original = assert(file:read("*a"))
        assert(file:close())
        files[#files + 1] = {Path = path, Original = original}
    end
    files[1].Updated = replaceAttributes(files[1].Original, "familiar", 'id="0"', {
        name = translation.Fan.Name, description = translation.Fan.Description,
    })
    files[2].Updated = replaceAttributes(files[2].Original, "card", 'hud="Mizuki Experimental Capsule"', {
        name = translation.Capsule.Name, description = translation.Capsule.Description,
    })
    local lines = {'<?xml version="1.0" encoding="UTF-8"?>', '<collectibles>',
        '    <collectible id="0">'}
    for _, text in ipairs(translation.Fan.NativeInfo) do
        lines[#lines + 1] = '        <info text="' .. xmlText(text) .. '" />'
    end
    lines[#lines + 1] = '    </collectible>'
    lines[#lines + 1] = '</collectibles>'
    local count = 0
    for _ in files[3].Original:gmatch("<collectible%s") do count = count + 1 end
    assert(count == 1 and files[3].Original:find('id="0"', 1, true),
        "Unexpected info_display entries")
    files[3].Updated = table.concat(lines, "\n") .. "\n"

    -- Stage every file before touching a loaded XML. Renames can fail if a
    -- process holds the file; restore earlier replacements and retry later.
    local changed = false
    for _, entry in ipairs(files) do
        entry.Changed = entry.Original:gsub("\r\n", "\n") ~= entry.Updated:gsub("\r\n", "\n")
        if entry.Changed then
            changed = true
            local file = assert(io.open(entry.Path .. ".language-new", "wb"))
            assert(file:write(entry.Updated))
            assert(file:close())
        end
    end
    local ok, errorMessage = pcall(function()
        for _, entry in ipairs(files) do
            if entry.Changed then
                assert(os.rename(entry.Path, entry.Path .. ".language-old"))
                entry.Backup = true
                assert(os.rename(entry.Path .. ".language-new", entry.Path))
                entry.Replaced = true
            end
        end
    end)
    if not ok then
        for index = #files, 1, -1 do
            local entry = files[index]
            if entry.Backup then
                if entry.Replaced then assert(os.remove(entry.Path)) end
                assert(os.rename(entry.Path .. ".language-old", entry.Path))
            end
        end
        error(errorMessage, 0)
    end
    for _, entry in ipairs(files) do
        if entry.Backup then assert(os.remove(entry.Path .. ".language-old")) end
    end
    return changed
end

local function attemptNativeXml()
    if not nativeXmlPending then return end
    if not io or not io.open or not os or not os.rename or not os.remove then
        nativeXmlStatus, nativeXmlPending = "unavailable", false
        return
    end
    if not modDirectory then
        nativeXmlStatus, nativeXmlPending = "path", false
        return
    end
    local ok, changed = pcall(replaceNativeXml)
    if ok then
        nativeXmlRequiresRestart = nativeXmlRequiresRestart or changed
        nativeXmlStatus = nativeXmlRequiresRestart and "restart" or "ready"
        nativeXmlPending = false
    else
        nativeXmlStatus = "pending"
        nativeXmlNextAttempt = Game():GetFrameCount() + 30
        Isaac.DebugString("[Mizuki Language] " .. tostring(changed))
    end
end

local function requestNativeXml()
    nativeXmlPending = true
    attemptNativeXml()
end

local function setLanguage(language)
    selectedLanguage = normalizeLanguage(language)
    local root = readSettingsRoot()
    root.Settings = type(root.Settings) == "table" and root.Settings or {}
    root.Settings.Language = selectedLanguage
    Mizuki:SaveData(json.encode(root))
    requestNativeXml()
end

local menuRegistered = false
local function registerLanguageMenu()
    if not REPENTANCE_PLUS or not ModConfigMenu or menuRegistered then return end
    local menu = ModConfigMenu
    -- Replace this mod's own entries on Lua reload; leave other categories alone.
    menu.RemoveSubcategory("Mizuki", "Language")
    menu.AddSetting("Mizuki", "Language", {
        Type = menu.OptionType.NUMBER,
        Minimum = 1, Maximum = 2,
        CurrentSetting = function() return selectedLanguage == "zh" and 2 or 1 end,
        Display = function()
            return selectedLanguage == "zh" and "语言：中文" or "Language: English"
        end,
        OnChange = function(value) setLanguage(value == 2 and "zh" or "en") end,
        Info = {"Language for Mizuki. Built-in item names and descriptions apply after restarting.",
            "EID uses its own language setting."},
    })
    menu.AddText("Mizuki", "Language", function()
        local messages = {
            en = {idle = "", unavailable = "File access unavailable (--luadebug required)",
                path = "Mod folder could not be located", pending = "File replacement pending",
                restart = "Files updated. Restart the game to apply.", ready = "Language files are up to date"},
            zh = {idle = "", unavailable = "无法访问文件（需要 --luadebug）",
                path = "无法定位模组目录", pending = "等待替换语言文件",
                restart = "文件已更新，重启游戏后生效", ready = "语言文件已是当前选择"},
        }
        return messages[Mizuki.GetLanguage()][nativeXmlStatus]
    end)
    menuRegistered = true
end

registerLanguageMenu()
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerLanguageMenu)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, requestNativeXml)
Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if nativeXmlPending and Game():GetFrameCount() >= nativeXmlNextAttempt then attemptNativeXml() end
end)
