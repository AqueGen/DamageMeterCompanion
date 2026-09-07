# DamageMeterTweaks - in-game checklist

Everything the headless build could not verify, in the order it makes sense to run. No agent performed any of these; none of them are claimed as passing.

Setup: `/reload`, then hit a target dummy so the meter has data.

## 1. It loads at all

- [ ] No Lua error on login.
- [ ] `/dmt` opens the settings panel.
- [ ] `/dmt probe` prints a line. No message about an unlisted damage meter type appeared at login.

## 2. The probe - run this early, two answers depend on it

- [ ] Out of combat: `/dmt probe`. Expected all four `secret` values `false` and `SetCVar ... allowed: true`.
- [ ] In combat, still hitting the dummy: `/dmt probe`. The design expects `totalAmount`, `amountPerSecond` and `sessionTotalAmount` `true`, `deathRecapID` `false`.

If the values are **not** secret in combat, the number formatting covers combat too - better than planned, and worth telling me so I can widen it. If `SetCVar` is refused in combat, the toggle binding prints a message instead of working, which is already handled.

## 3. Numbers

- [ ] Out of combat, the bars read like `56.72M`, `56.72M (40.6K)` or `56.72M (40.6K) 18.0%` depending on the Edit Mode Numbers setting, not `56716 K`.
- [ ] The spell breakdown reads the full form `56.72M (40.6K) 18.0%` regardless of that setting - it always forces Complete.

## 4. Hover

- [ ] Hovering a bar opens the spell breakdown after a short delay.
- [ ] Moving the cursor off the bar closes it.
- [ ] Moving the cursor from the bar into the breakdown keeps it open.
- [ ] Left-clicking a bar pins the breakdown; it survives the cursor leaving and any later hover.
- [ ] Hovering a row in the Deaths display does **not** open the death recap. Clicking it still does.
- [ ] `/dmt hover` turns hover off and clicking still works.

## 5. Right-click menu

- [ ] Right-clicking a bar opens a menu at the cursor: three type submenus, a segment submenu, window actions.
- [ ] Picking Healing Done switches the window, and the header dropdown agrees.
- [ ] Picking a segment switches it, and the header segment widget agrees.
- [ ] Show new window and Hide window work; Hide is greyed out on window 1.
- [ ] The menu has a Settings entry and it opens the panel.
- [ ] **In combat**: hover a bar to open the breakdown, then right-click and switch type. No Lua error. This is the one path where our menu drives Blizzard's refresh over secret values, and nothing headless could check it.
- [ ] In the Deaths display, the right column shows a time like `3m 22s`, not a number.

## 6. Snapping and size matching

Open two more windows from the menu so all three exist.

- [ ] Dragging window 2 so its top edge nears the bottom of window 1 makes it jump flush, and its width becomes window 1's.
- [ ] Moving window 1 in Edit Mode carries window 2 with it.
- [ ] Resizing window 1 in Edit Mode resizes window 2's width to match, clamped at 600 if window 1 is wider.
- [ ] Dragging window 2 well away breaks the link and it moves freely.
- [ ] Snapping window 3 to the right of window 2 matches heights instead of widths.
- [ ] Right-clicking a bar in a linked window shows Match width and Match height; toggling them takes effect immediately and the menu stays open.
- [ ] `/reload` keeps every link and every matched size.
- [ ] Window 1 cannot be dragged at all, so it never becomes a snap source.

These four came out of the Task 6 review and are the ones most likely to catch something:

- [ ] Chain of three: 3 snapped under 2, 2 snapped under 1. Resizing window 1 resizes **both** 2 and 3.
- [ ] Lock window 2 from the settings dropdown, then resize window 1. Window 2 must **not** resize.
- [ ] Detach window 2, `/reload`. It must come back where you left it, not at a default offset.
- [ ] Hide a snapped window, then show it again. It must come back attached.

## 7. Transparency and layer

- [ ] With the mouse away the meter sits at roughly 40 percent of its Edit Mode transparency.
- [ ] Moving the mouse over it brings it to the Edit Mode value; moving away dims it again.
- [ ] Hovering a bar opens the breakdown; moving the cursor **into** the breakdown keeps both at full alpha, and leaving it dims them again within about a fifth of a second.
- [ ] Open a new window from the menu or its keybind. It picks up the idle transparency and the chosen layer immediately, without a reload.
- [ ] Changing Transparency in Edit Mode still works and both states move with it.
- [ ] A window set to uninteractable stays dim. Expected - its mouse is disabled.
- [ ] The Layer dropdown moves the meter above other frames, with the breakdown still in front of the bars.

## 8. Key bindings

- [ ] A DamageMeterTweaks category exists in Key Bindings with three bindings.
- [ ] The toggle hides and shows the whole meter out of combat.
- [ ] Pressed in combat it either works or prints a message. It never throws.
- [ ] On a character that has never opened a secondary window, the "window 3" key opens window **3**, not window 2.

## 9. Settings panel

- [ ] `/dmt` opens it with the behaviour options and a Windows subcategory.
- [ ] Every checkbox and slider changes behaviour immediately and survives a reload.
- [ ] The Windows page lists three rows. Window 1 says its size is controlled by Edit Mode and its Shown box is disabled.
- [ ] Snapping two windows and reopening the page shows the link and the match flags.
- [ ] Detach drops the link and the window then moves freely.
