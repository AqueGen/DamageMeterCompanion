package.path = "./?.lua;" .. package.path

local Realms = require("LogLinkRealms")
local Link = require("LogLinkUrl")

local EU, US = 3, 1

describe("Realms.SlugFor", function()
  it("derives the ordinary case", function()
    assert.equals("silvermoon", Realms.SlugFor("Silvermoon"))
    assert.equals("tarren-mill", Realms.SlugFor("Tarren Mill"))
    assert.equals("kelthuzad", Realms.SlugFor("Kel'Thuzad"))
    -- The typographic apostrophe too, removed whole rather than through a
    -- character class: one of its three bytes is also a continuation byte of
    -- ordinary Cyrillic letters.
    assert.equals("kelthuzad", Realms.SlugFor("Kel\226\128\153Thuzad"))
  end)

  it("knows the realms no rule can derive", function()
    -- Twenty Russian realms carry a Latin slug with no relationship to their
    -- letters, and nothing in the game client knows the pairing.
    assert.equals("fordragon", Realms.SlugFor("Дракономор"))
    assert.equals("booty-bay", Realms.SlugFor("Пиратская бухта"))
    assert.equals("thermaplugg", Realms.SlugFor("Термоштепсель"))
    assert.equals("soulflayer", Realms.SlugFor("Свежеватель Душ"))
    -- And three Latin ones whose punctuation the rule would keep.
    assert.equals("azjolnerub", Realms.SlugFor("Azjol-Nerub"))
    assert.equals("arakarahm", Realms.SlugFor("Arak-arahm"))
  end)

  it("finds an exception by the spelling the game uses", function()
    -- A cross-realm name arrives as "Name-Realm" with the realm's spaces already
    -- stripped, while the table is keyed by the realm's real name. Both have to
    -- reach the same row or every multi-word Russian realm loses its link.
    assert.equals("booty-bay", Realms.SlugFor("Пиратскаябухта"))
    assert.equals("howling-fjord", Realms.SlugFor("Ревущийфьорд"))
    assert.equals("soulflayer", Realms.SlugFor("СвежевательДуш"))
  end)

  it("answers nil rather than guessing", function()
    assert.is_nil(Realms.SlugFor(nil))
    assert.is_nil(Realms.SlugFor(""))
  end)

  it("leaves non-ASCII case alone when it has to derive", function()
    -- string.lower is locale-dependent above 0x7F, so folding the whole string
    -- can mangle the letters. An unknown Cyrillic realm produces a slug that is
    -- wrong either way, but it must not produce a corrupt one.
    assert.equals("Нетакогореалма", Realms.SlugFor("Нетакогореалма"))
  end)
end)

describe("Link.For", function()
  it("lands on the Mythic+ season rather than the raid tab", function()
    -- The whole reason this exists: Archon and Raider.IO both copy a link and
    -- both land on the raid page, and the season has to be switched by hand.
    assert.equals("https://www.warcraftlogs.com/character/eu/silvermoon/medvedyk?zone=55",
      Link.For("Medvedyk", "Silvermoon", EU))
  end)

  it("uses the site's slug, not the realm's name", function()
    assert.equals("https://www.warcraftlogs.com/character/eu/tarren-mill/cutlers?zone=55",
      Link.For("Cutlers", "Tarren Mill", EU))
    assert.equals("https://www.warcraftlogs.com/character/eu/gordunni/ктулху?zone=55",
      Link.For("Ктулху", "Гордунни", EU))
  end)

  it("follows the region the client is in", function()
    assert.equals("https://www.warcraftlogs.com/character/us/silvermoon/medvedyk?zone=55",
      Link.For("Medvedyk", "Silvermoon", US))
  end)

  it("can be asked for the plain character page", function()
    assert.equals("https://www.warcraftlogs.com/character/eu/silvermoon/medvedyk",
      Link.For("Medvedyk", "Silvermoon", EU, false))
  end)

  it("says what is missing instead of building a broken link", function()
    -- A link to the wrong page is worse than no link: it looks like an answer.
    local url, problem = Link.For("Medvedyk", nil, EU)
    assert.is_nil(url)
    assert.equals("no realm for Medvedyk", problem)

    url, problem = Link.For("", "Silvermoon", EU)
    assert.is_nil(url)
    assert.equals("no character name", problem)

    url, problem = Link.For("Medvedyk", "Silvermoon", 99)
    assert.is_nil(url)
    assert.equals("unknown region", problem)
  end)
end)

describe("Realms.Lower", function()
  it("folds Cyrillic by arithmetic, not by the client's locale", function()
    -- string.lower is the C library byte by byte, and what it does above 0x7F
    -- depends on the locale - so a link built with it is unchanged on one client
    -- and corrupt on another. In UTF-8 the fold is a fixed offset with one carry
    -- into the second lead byte.
    assert.equals("ктулху", Realms.Lower("Ктулху"))
    assert.equals("ёмии", Realms.Lower("Ёмии"))
    assert.equals("ясеневыйлес", Realms.Lower("ЯсеневыйЛес"))
    -- The whole alphabet, both halves of the range and the carry between them.
    assert.equals("абвгдежзийклмноп", Realms.Lower("АБВГДЕЖЗИЙКЛМНОП"))
    assert.equals("рстуфхцчшщъыьэюя", Realms.Lower("РСТУФХЦЧШЩЪЫЬЭЮЯ"))
  end)

  it("leaves what is already lowercase, and ASCII, alone", function()
    assert.equals("ктулху", Realms.Lower("ктулху"))
    assert.equals("medvedyk", Realms.Lower("Medvedyk"))
    -- A Latin letter with a diacritic is not Cyrillic and must survive untouched:
    -- its bytes are in the same 0x80-0xBF continuation range the pattern scans.
    assert.equals("hødzere", Realms.Lower("Hødzere"))
  end)
end)
