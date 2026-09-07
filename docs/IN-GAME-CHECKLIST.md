# DamageMeterCompanion - in-game checklist

Everything the headless build cannot verify. Rewritten 2026-09-07 evening after the taint cut (see DECISIONS.md); windows beyond Blizzard's three and the addon's own right-click menu are gone because those features are; hover is back as a frame of our own.

Setup: `/reload`, hit a target dummy so the meter has data, keep BugSack open. **The bar for every section is the same: BugSack stays empty, in combat and out.**

## 1. It loads at all

- [ ] No Lua error on login.
- [ ] `/dmc` opens the settings panel; the meter's own gear menu has a DamageMeterCompanion settings entry that opens it too, and in combat prints a message instead.
- [ ] `/dmc probe` and `/dmc diag` print without error.

## 2. Numbers

- [ ] In combat the bars read `56.72M` or `56.72M (40.6K)` depending on the Edit Mode Numbers setting, steady, no flicker back to `56716 K`.
- [ ] Complete mode shows the percentage only when the values are readable, which is out of combat once Blizzard has refreshed with plain rows.
- [ ] The spell breakdown (opened with Blizzard's own click) reads the full form.
- [ ] Turning Readable numbers off puts Blizzard's text back within a moment; on again re-formats.
- [ ] A full pull with the breakdown open and closed, then leave combat: **no `attempt to compare` warnings**.

## 2b. Hover and the type menu

- [ ] Resting the cursor on your own bar shows the spell panel beside the window; moving off closes it; moving into the panel keeps it.
- [ ] In combat the panel shows and updates, BugSack stays empty.
- [ ] In a party, hovering another member's bar shows their spells when their class is unique in the party; a duplicate class shows nothing.
- [ ] Clicking a bar opens Blizzard's breakdown and the hover panel stays away while it is shown.
- [ ] The header type dropdown ends with Lock/Unlock, Hide window, Reset and DamageMeterCompanion settings, and each works.

## 3. Snapping and size matching

- [ ] Dragging window 2 so its top edge nears the bottom of window 1 shows the green bars, and on release it sits flush and matches window 1's width.
- [ ] Moving window 1 in Edit Mode carries window 2 with it.
- [ ] Resizing window 1 in Edit Mode resizes window 2's width to match.
- [ ] Dragging window 2 well away breaks the link.
- [ ] Snapping window 3 to the right of window 2 matches heights instead of widths.
- [ ] Chain: 3 under 2, 2 under 1. Resizing window 1 resizes both.
- [ ] Lock window 2, resize window 1: window 2 does not resize.
- [ ] Detach window 2, `/reload`: it comes back where it was.
- [ ] Hide a snapped window, show it again from the gear menu: it comes back attached.
- [ ] Dropping a window near a screen edge with no window near lands it flush; the bars show on the window's and the screen's edge.
- [ ] Gap of 6 on a linked window separates the pair by six pixels and survives a reload.
- [ ] `/reload` keeps every link and size.

## 4. Transparency and layer

- [ ] Mouse away: roughly 40 percent of the Edit Mode transparency. Mouse over: the Edit Mode value.
- [ ] Cursor moving from the bars into an open breakdown keeps both at full alpha; leaving dims them within about a fifth of a second.
- [ ] A window shown from the gear menu picks up the idle transparency and the layer immediately.
- [ ] Changing Transparency in Edit Mode still works and both states move with it.
- [ ] The Layer dropdown moves the meter above other frames, breakdown still in front of the bars.

## 5. Key bindings

- [ ] Three bindings under DamageMeterCompanion: toggle the meter, hide all extra windows, reset data.
- [ ] The toggle hides and shows the whole meter out of combat; in combat it works or prints a message, never throws.
- [ ] Hide all hides windows 2 and 3; they come back through the gear menu's Show new window.
- [ ] Reset clears the meter like the gear menu's Reset.

## 6. Settings panel

- [ ] The behaviour page has readable numbers, snapping, snap distance, idle transparency, layer, and at the bottom a Blizzard section with Enable Damage Meter and Auto Reset that mirror Gameplay Enhancements both ways.
- [ ] The Windows page lists three rows. A hidden slot says how to bring it back. Window 1's size boxes route through Edit Mode; a size Edit Mode refuses prints a message.
- [ ] Typing an out-of-range width comes back clamped. A locked window's boxes are greyed.
- [ ] Lock per row, Lock all and Unlock all agree with the gear menu's lock state.
- [ ] Hide on a row hides the window; the row stays.
- [ ] Snapping two windows and reopening the page shows the link, gap and match flags; Detach drops it.
- [ ] **After typing a size for window 1, open Edit Mode and press Save**: no "Interface action failed because of an addon".
