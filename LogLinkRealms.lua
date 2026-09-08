local _, ns = ...

local Realms = {}

-- Warcraft Logs addresses a character as /character/<region>/<realm>/<name>, and
-- that realm is the site's own slug rather than the realm's name. For most
-- realms the slug is derivable: lowercase, apostrophes dropped, spaces hyphened.
--
-- Twenty-three realms in this region are not derivable, and twenty of them are
-- Russian: a Cyrillic name with a Latin slug that has no relationship to its
-- letters. Nothing in the game client knows the pairing, so it is carried here.
-- Measured against the site's own realm list, not guessed.
local EXCEPTIONS = {
  ["Azjol-Nerub"] = "azjolnerub",
  ["Arak-arahm"] = "arakarahm",
  ["Aggra (Português)"] = "aggra-português",
  ["Азурегос"] = "azuregos",
  ["Борейская тундра"] = "borean-tundra",
  ["Вечная Песня"] = "eversong",
  ["Галакронд"] = "galakrond",
  ["Голдринн"] = "goldrinn",
  ["Гордунни"] = "gordunni",
  ["Гром"] = "grom",
  ["Дракономор"] = "fordragon",
  ["Король-лич"] = "lich-king",
  ["Пиратская бухта"] = "booty-bay",
  ["Подземье"] = "deepholm",
  ["Разувий"] = "razuvious",
  ["Ревущий фьорд"] = "howling-fjord",
  ["Свежеватель Душ"] = "soulflayer",
  ["Седогрив"] = "greymane",
  ["Страж Смерти"] = "deathguard",
  ["Термоштепсель"] = "thermaplugg",
  ["Ткач Смерти"] = "deathweaver",
  ["Черный Шрам"] = "blackscar",
  ["Ясеневый лес"] = "ashenvale",
}
Realms.EXCEPTIONS = EXCEPTIONS

-- ASCII only, by explicit byte range. string.lower is the C library's tolower
-- applied byte by byte, and what it does above 0x7F depends on the client's
-- locale - so folding a whole string can mangle the very Cyrillic names this
-- file exists to look up.
local function asciiLower(text)
  return (string.gsub(text or "", "[A-Z]", string.lower))
end

-- Cyrillic, folded by arithmetic rather than by tolower. In UTF-8 the capitals
-- А-Я are D0 90 through D0 AF and the smalls а-я are D0 B0 through D1 8F, so the
-- fold is a fixed offset with one carry into the second lead byte. Ё is the odd
-- one out at D0 81, folding to ё at D1 91.
--
-- This exists because the site canonicalises a character name to lowercase, and
-- about one player in eleven in this region has a Cyrillic name. string.lower
-- cannot do it - it is the C library byte by byte, and what it does above 0x7F is
-- a property of the client's locale - so a link built with it is either unchanged
-- or corrupt depending on who copies it.
local function cyrillicLower(text)
  return (string.gsub(text, "[\208\209][\128-\191]", function(pair)
    local lead, tail = string.byte(pair, 1, 2)
    if lead == 208 then
      if tail == 129 then return "\209\145" end          -- Ё
      if tail >= 144 and tail <= 159 then return string.char(208, tail + 32) end
      if tail >= 160 and tail <= 175 then return string.char(209, tail - 32) end
    end
    return pair
  end))
end

---@param text string|nil
---@return string
function Realms.Lower(text)
  return cyrillicLower(asciiLower(text))
end

-- The realm as the game spells it, from a name that may or may not carry one.
-- The game writes a cross-realm character as "Name-Realm" with the realm's
-- spaces already removed, while the exception table above is keyed by the realm's
-- real name - so both spellings have to find the same row.
local COMPACT = {}
for name, slug in pairs(EXCEPTIONS) do
  COMPACT[(string.gsub(name, " ", ""))] = slug
end

---@param realm string|nil
---@return string|nil slug
function Realms.SlugFor(realm)
  if type(realm) ~= "string" or realm == "" then return nil end
  local exact = EXCEPTIONS[realm] or COMPACT[realm]
  if exact then return exact end

  -- The derivable case. Apostrophes go, including the typographic one - removed
  -- as a whole three-byte substring, never inside a character class, because one
  -- of its bytes is also a continuation byte of ordinary Cyrillic letters.
  local text = string.gsub(realm, "\226\128\153", "")
  text = string.gsub(text, "'", "")
  text = string.gsub(text, " ", "-")
  return asciiLower(text)
end

if ns then ns.Realms = Realms end
return Realms
