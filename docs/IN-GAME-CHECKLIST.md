# DamageMeterCompanion - in-game checklist

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

- [ ] A DamageMeterCompanion category exists in Key Bindings with three bindings.
- [ ] The toggle hides and shows the whole meter out of combat.
- [ ] Pressed in combat it either works or prints a message. It never throws.
- [ ] On a character that has never opened a secondary window, the "window 3" key opens window **3**, not window 2.

## 8b. Extra windows and chaining

Everything in this section is new and none of it has ever run.

- [ ] `/dmt` → Windows. On a fresh character the page lists three rows, and ticking row 2's Shown box creates window 2.
- [ ] **Add window** creates a fourth. It draws bars, and its own gear dropdown offers type, segment, lock, uninteractable, minimize and hide, each of which works.
- [ ] The new window's appearance matches Blizzard's. Change Bar Height in Edit Mode and confirm the new window changes too.
- [ ] Hover, the right-click menu, the idle transparency and the snap preview all work on the new window, not just on Blizzard's.
- [ ] Add two more, chain them: 4 under 3, 5 under 4, 6 under 5. Move window 1 in Edit Mode and confirm the whole chain follows.
- [ ] `/reload`. Every window, its size, its position and every link survives.
- [ ] Remove the middle window of a chain. The one that pointed at it comes free and stays where it was, including after a reload.
- [ ] Hide one of our windows, then click Add window. The hidden one comes back rather than a new one being created - that is deliberate and mirrors Blizzard.
- [ ] Give a window a bar height override of 20 and a text size of 80. Both take effect on that window only. Clearing the box returns it to following Edit Mode.
- [ ] Type 0 into a bar height override. It is refused and the box comes back blank.

## 8c. Snap preview and gap

- [ ] Dragging a window near another shows a green bar on both edges that will meet, and nothing when out of range.
- [ ] The bars vanish on release, and turning snapping off in the panel stops them appearing at all.
- [ ] The bars appear on the correct edges for all four directions - below, above, left and right.
- [ ] Set a gap of 6 on a linked window. The pair separates by six pixels and the value survives a reload.

## 8d. Sizes

- [ ] Type a width for window 1. It resizes, and the value survives a reload.
- [ ] An out-of-range width comes back clamped in the box.
- [ ] A size Edit Mode refuses prints a message rather than silently reverting.
- [ ] Lock a window from its gear dropdown. Its size boxes grey out and a typed size is refused.
- [ ] **After typing a size for window 1, open Edit Mode and press Save.** This is the one place the addon writes into Blizzard's Edit Mode layout from a tainted stack. Watch for "Interface action failed because of an addon" or a layout that fails to persist. If either happens, tell me - the fix is to drop the panel's control over window 1's size and leave it to Edit Mode's own slider.

## 9. Settings panel

- [ ] `/dmt` opens it with the behaviour options and a Windows subcategory.
- [ ] Every checkbox and slider changes behaviour immediately and survives a reload.
- [ ] The Windows page lists three rows. Window 1 says its size is controlled by Edit Mode and its Shown box is disabled.
- [ ] Snapping two windows and reopening the page shows the link and the match flags.
- [ ] Detach drops the link and the window then moves freely.

## 10. Panel lock and Remove

- [ ] The Windows page has a lock box per row. Ticking it locks that window: it cannot be dragged, and its size boxes grey out.
- [ ] Window 1's lock box is disabled.
- [ ] Remove is now enabled on Blizzard's windows 2 and 3 while they are shown. Clicking it puts the window away and the row stays as an empty slot.
- [ ] Removing a window that something was attached to leaves that other window where it was.
- [ ] The right-click menu no longer carries Match width and Match height. Both still work from the Windows page.
