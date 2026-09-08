local _, ns = ...

local Realms = ns and ns.Realms or require("LogLinkRealms")

local Link = {}

-- The Mythic+ zone the link should land on. Warcraft Logs numbers its zones, and
-- a character page without one opens on the raid tab - which is the whole reason
-- this addon exists, because both Archon and Raider.IO already copy a link and
-- both land there.
--
-- One number per season, changed by hand. There is no API call that maps "the
-- current Mythic+ season" to a Warcraft Logs zone id, and guessing it wrong sends
-- the reader to an empty page rather than to no page.
Link.ZONE = 55
Link.ZONE_NAME = "Mythic+ Season 2"

-- Blizzard's region ids against the site's own path segment. GetCurrentRegion
-- returns the number; the site wants the letters.
local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }
Link.REGIONS = REGIONS

---@param name string
---@param realm string
---@param regionID number|nil @defaults to the client's own region
---@param zone number|nil @defaults to Link.ZONE, false for no zone at all
---@return string|nil url
---@return string|nil problem @why there is no url
function Link.For(name, realm, regionID, zone)
  if type(name) ~= "string" or name == "" then return nil, "no character name" end

  local slug = Realms.SlugFor(realm)
  if not slug then return nil, "no realm for " .. name end

  local region = REGIONS[regionID or 0]
  if not region then return nil, "unknown region" end

  -- The name is lowercased the same way the realm is: the site accepts either
  -- case, and matching what it canonicalises to keeps the copied link identical
  -- to the one the reader would get from the site itself.
  local character = Realms.Lower(name)

  local url = string.format("https://www.warcraftlogs.com/character/%s/%s/%s",
    region, slug, character)
  if zone == false then return url end
  return url .. "?zone=" .. tostring(zone or Link.ZONE)
end

if ns then ns.Link = Link end
return Link
