# DamageMeterCompanion

A companion for Blizzard's built-in Damage Meter. It computes nothing itself - every number you see is still Blizzard's - and it never touches the meter's data or its windows' content. What it adds is layout and readability.

Retail only, patch 12.1. No libraries, no dependencies.

## What it adds

**Readable numbers.** `56716 K` becomes `56.72M`, in combat too. The abbreviation is the client's own routine, which accepts the Secret values an addon may not read and hands back a string the bar may show - the same chain Details paints with. The percentage is the one part that needs arithmetic, so it appears only when the values are readable, out of combat.

**Window snapping.** Drag a window near another and a green bar shows which edges will meet. Release and they attach: the pair moves together, and the axis you joined on matches size. Windows chain, a gap between them is configurable, and a window dropped near a screen edge lands flush with it.

**A window page.** `/dmc` lists Blizzard's three windows with their exact size in pixels, what is attached to what, the gap, a lock per window and Lock all / Unlock all. Window 1's size is routed through Edit Mode, which is the only thing allowed to set it.

**Transparency and layer.** The meter dims when the mouse is away and comes back when it is over it, as a fraction of the Edit Mode transparency you already set. The frame layer is a dropdown, for when another addon covers the meter.

**One place for the meter's settings.** The game's own Enable and Auto Reset switches are mirrored at the bottom of the page, marked as Blizzard's, and the meter's gear menu has an entry that opens the page (out of combat - in combat an entry of ours would taint the menu's own layout).

**Key bindings** to show or hide the meter, hide every extra window, and reset the data.

## Commands

- `/dmc` (or `/dmt`) - settings
- `/dmc format`, `/dmc snap` - toggle one feature
- `/dmc diag` - what the addon sees, per window; useful when reporting a bug
- `/dmc probe` - what the API says about Secret values right now

## What it deliberately does not do, and why

On 12.x the meter's data is Secret to addons in combat, and anything an addon writes into Blizzard's meter windows taints them: their own refresh then logs a warning per row, in combat, until you reload. So this addon never opens Blizzard's own breakdown (click it - that is Blizzard's own, untainted handler), does not switch a window's type or segment (the header dropdowns do, untainted), does not create windows beyond Blizzard's three, and does not show a hidden window (the gear menu's Show new window does). Each of those was built, seen to taint the meter, and removed. The reasoning with line references is in `docs/DECISIONS.md`.

Three things on the Windows page do go through Blizzard's code and taint it the same way: locking a window, setting a size, and showing a hidden slot. They stay because a reload clears them completely - Blizzard restores the lock, the size and the window itself at login. So the first time you use one of them in a session the addon offers a reload, once. Dragging, snapping and the gap are position only and never need it.

No parsing, no storage, no analysis, no skins, no report-to-chat. Blizzard's meter is the meter. If you want a meter of your own, use Details.

## Development

`busted tests` runs the pure-logic suite - number composition, snap geometry, the drop preview and the transparency rules. Everything frame-bound is verified in game against `docs/IN-GAME-CHECKLIST.md`.
