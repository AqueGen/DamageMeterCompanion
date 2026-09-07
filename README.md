# DamageMeterCompanion

A companion for Blizzard's built-in Damage Meter. Every number you see is still Blizzard's - this addon changes how you drive the meter and how its windows are laid out, and computes nothing.

Retail only, patch 12.1. No libraries, no dependencies.

## What it adds

**A right-click menu on the bars.** Type, segment, lock, new window, hide window, reset, settings - all where the bar is, instead of two trips to the header dropdowns.

**Readable numbers.** `56716 K` becomes `56.72M`, in combat too. The abbreviation is the client's own routine, which accepts the Secret values an addon may not read and hands back a string the bar may show - the same chain Details paints with. The percentage is the one part that needs arithmetic, so it appears only out of combat.

**Window snapping.** Drag a window near another and a green bar shows which edges will meet. Release and they attach: the pair moves together, and the axis you joined on matches size. Any window can attach to any other, in a chain as long as you like. A window dropped near a screen edge lands flush with it.

**More than three windows.** Blizzard stops at three. This addon adds its own beyond that, with their own type, segment, lock, size and position, all saved per character.

**A window page.** `/dmc` lists every window with its exact size in pixels, what is attached to what, the gap between them, a per-window bar height and text size override, a lock, and Lock all / Unlock all. Window 1's size is routed through Edit Mode, which is the only thing allowed to set it.

**Transparency and layer.** The meter dims when the mouse is away and comes back when it is over it, as a fraction of the Edit Mode transparency you already set. The frame layer is a dropdown, for when another addon covers the meter.

**Key bindings** for showing and hiding the meter, toggling windows 2 and 3, hiding and restoring every extra window at once, and resetting the data.

## Commands

- `/dmc` (or `/dmt`, the old name's command) - settings, also reachable from the gear dropdown on any meter window
- `/dmc menu`, `/dmc format`, `/dmc snap` - toggle one feature
- `/dmc diag` - what our hooks reached, per window; for reporting a bug
- `/dmc probe` - what the API says about Secret values right now

## What it deliberately does not do

No parsing, no storage, no analysis, no skins, no report-to-chat. Blizzard's meter is the meter. Details is the addon to use if you want a meter of your own.

## Development

`busted tests` runs the pure-logic suite - snap geometry, the window registry, the drop preview and the transparency rules. Everything frame-bound is verified in game against `docs/IN-GAME-CHECKLIST.md`, because none of it can run headless. `docs/DECISIONS.md` records the engine facts the design rests on and the features that were deliberately left out.
