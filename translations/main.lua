Mizuki.Translations = {
    en = include("translations/en"),
    zh = include("translations/zh"),
}

-- Native HUD text follows the game language. EID registers both translations
-- independently and continues to follow EID's own language setting.
function Mizuki.GetTranslation(language)
    language = language or Options.Language
    if language == "zh_cn" then language = "zh" end
    if language == "en_us" then language = "en" end
    return Mizuki.Translations[language] or Mizuki.Translations.en
end
