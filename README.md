# DamageMeterCompanion

Convenience for Blizzard's built-in Damage Meter, added from the outside. Every number you see is still Blizzard's - this addon changes how you drive the meter and how its windows are laid out, and computes nothing.

Retail only, patch 12.1. No libraries, no dependencies.

## What it adds

**Hover instead of click.** Resting the cursor on a bar opens the spell breakdown. Clicking still pins it, so the breakdown stays put while you look at something else. Rows in the Deaths display are left alone - those open the death recap, and hovering one would fire it by accident.

**A right-click menu on the bars.** Type, segment, lock, new window, hide window, reset, settings - all where the bar is, instead of two trips to the header dropdowns.

**Readable numbers.** `56716 K` becomes `56.72M`. The values are Secret in combat, so the formatting appears when the pull ends; that is a rule of the 12.x API, not a delay this addon chose.

**Window snapping.** Drag a window near another and a green bar shows which edges will meet. Release and they attach: the pair moves together, and the axis you joined on matches size. Any window can attach to any other, in a chain as long as you like.

**More than three windows.** Blizzard stops at three. This addon adds its own beyond that, with their own type, segment, lock, size and position, all saved per character.

**A window page.** `/dmt` lists every window with its exact size in pixels, what is attached to what, the gap between them, a per-window bar height and text size override, and a lock. Window 1's size is routed through Edit Mode, which is the only thing allowed to set it.

**Transparency and layer.** The meter dims when the mouse is away and comes back when it is over it, as a fraction of the Edit Mode transparency you already set. The frame layer is a dropdown, for when another addon covers the meter.

**Key bindings** for showing and hiding the meter and for toggling windows 2 and 3.

## Commands

- `/dmt` - settings
- `/dmt hover`, `/dmt menu`, `/dmt format`, `/dmt snap` - toggle one feature
- `/dmt diag` - what our hooks reached, per window; for reporting a bug
- `/dmt probe` - what the API says about Secret values right now

## What it deliberately does not do

No parsing, no storage, no analysis, no skins, no report-to-chat. Blizzard's meter is the meter. Details is the addon to use if you want a meter of your own.

## Development

`busted tests` runs the pure-logic suite - number formatting, snap geometry, the window registry, the drop preview and the transparency rules. Everything frame-bound is verified in game against `docs/IN-GAME-CHECKLIST.md`, because none of it can run headless. `docs/DECISIONS.md` records the engine facts the design rests on and the features that were deliberately left out.
