# Changelog

## [0.4.0](https://github.com/AqueGen/DamageMeterCompanion/compare/v0.3.0...v0.4.0) (2026-09-07)


### ⚠ BREAKING CHANGES

* cut every path that writes into Blizzard's meter windows - hover, the bar menu, addon windows, showing a window from addon code - so combat stays warning-free
* remove readable numbers - the values are Secret to addons in combat and a format that only holds between pulls is worse than none
* rename to DamageMeterCompanion, migrate saved variables, add a settings entry to the meter's own dropdown

### Features

* /dmc entryhooks isolates the InitEntry hooks from the taint warning ([2702498](https://github.com/AqueGen/DamageMeterCompanion/commit/270249801679115a0a4b8dc426ef8b084bb3b2a8))
* /dmt diag reports which windows our per-window hooks reached ([abfccbe](https://github.com/AqueGen/DamageMeterCompanion/commit/abfccbef0e5a590449a91065bb832843d1a3334a))
* a settable gap between linked windows ([8c2fde7](https://github.com/AqueGen/DamageMeterCompanion/commit/8c2fde71a67c51f4eb258545287013a5d99104c9))
* addon skeleton, core bootstrap and secrecy probe ([a8ead59](https://github.com/AqueGen/DamageMeterCompanion/commit/a8ead59b3283cdae5b52c1a872cdef2f5d47187c))
* cut every path that writes into Blizzard's meter windows - hover, the bar menu, addon windows, showing a window from addon code - so combat stays warning-free ([2ee52e0](https://github.com/AqueGen/DamageMeterCompanion/commit/2ee52e08355c9e0e771dbe4f53acf24581b18c0f))
* extra meter windows through a proxy owner ([dc1a5ed](https://github.com/AqueGen/DamageMeterCompanion/commit/dc1a5ed1e15a7d88a6f64cc7b3cdd69da163a1a5))
* idle transparency and configurable strata ([5e08147](https://github.com/AqueGen/DamageMeterCompanion/commit/5e081470a7629957f1a1d94103853e4d05cd6f72))
* key bindings for the meter and its windows ([97d7291](https://github.com/AqueGen/DamageMeterCompanion/commit/97d7291d9c21ba6006886e812c74c24af3ae2232))
* keys to reset the data and to hide or restore every extra window, Lock all / Unlock all in the panel, and snapping to the screen edges ([c8a8113](https://github.com/AqueGen/DamageMeterCompanion/commit/c8a81134fa5d3a5a80d54f152d8176ed3865c2a5))
* magnetic window snapping with size matching ([976b919](https://github.com/AqueGen/DamageMeterCompanion/commit/976b9199faa70c733363d5fec96436de6795e2bd))
* mirror the game's own Enable and Auto Reset switches at the bottom of the settings page, marked as Blizzard's ([512906d](https://github.com/AqueGen/DamageMeterCompanion/commit/512906d57cf2bd32be019d3f8ff2af72e72733b9))
* open the spell breakdown on hover ([869c9c2](https://github.com/AqueGen/DamageMeterCompanion/commit/869c9c2cdd88bf4af94799d84e1f3f06eab041ae))
* pixel-precise sizes for every window including the primary ([3552f23](https://github.com/AqueGen/DamageMeterCompanion/commit/3552f230ac660f293358c251ddab00c6320be4b7))
* probe reports whether the rendered bar text is readable ([857076e](https://github.com/AqueGen/DamageMeterCompanion/commit/857076ef0bbf617c302e4b70d227bf2ac51dca99))
* quick type buttons, per-window lock in the panel, match flags out of the menu ([94518ad](https://github.com/AqueGen/DamageMeterCompanion/commit/94518adae2f628aa57cc24c2e642af6d9285903b))
* readable number formatting on meter entries ([79779a2](https://github.com/AqueGen/DamageMeterCompanion/commit/79779a2522fd098a0505def41cd903ac4e10c1d0))
* readable numbers are back, painted the way Details does it - the client abbreviates the Secret value and the bar shows the result ([434ab82](https://github.com/AqueGen/DamageMeterCompanion/commit/434ab823fddfc144e7fe7b2bfc932b54a7a83826))
* remove readable numbers - the values are Secret to addons in combat and a format that only holds between pulls is worse than none ([a74e9c4](https://github.com/AqueGen/DamageMeterCompanion/commit/a74e9c45d1f0562598591acc8a59c83e4ab2fd03))
* Remove works on Blizzard windows 2 and 3, and diag reports anchors ([b4b10b1](https://github.com/AqueGen/DamageMeterCompanion/commit/b4b10b1331ef307b30f8f363f45f52d2ac0919db))
* rename to DamageMeterCompanion, migrate saved variables, add a settings entry to the meter's own dropdown ([91106a6](https://github.com/AqueGen/DamageMeterCompanion/commit/91106a68536df97aa2079a284b7c7bb42d049796))
* right-click menu for type, segment and window actions ([89b1ccd](https://github.com/AqueGen/DamageMeterCompanion/commit/89b1ccd1080a4172a0faefc38bc653e76308711e))
* settings panel with behaviour options and a window table ([264300d](https://github.com/AqueGen/DamageMeterCompanion/commit/264300d3b38c4c046bab9af979034943ef2cee87))
* show which edge a drag is about to snap to ([16c5e29](https://github.com/AqueGen/DamageMeterCompanion/commit/16c5e297f221d66888947de28fc89cdac6b37ed5))
* snap geometry and link bookkeeping ([868c674](https://github.com/AqueGen/DamageMeterCompanion/commit/868c674bfaf72c05746d994bd1a2ae92c42ee49f))
* snap preview geometry ([62e730e](https://github.com/AqueGen/DamageMeterCompanion/commit/62e730e2cfaad86edde853b79df6d1b635f39bcb))
* variable-length window list with add, remove, gap and overrides ([4368b2f](https://github.com/AqueGen/DamageMeterCompanion/commit/4368b2f5026c773e996670e440a1430971aecbab))
* window registry replacing the hardcoded three ([13d7061](https://github.com/AqueGen/DamageMeterCompanion/commit/13d7061c6a36a77879ebfff7eb3c36fb8e899db5))


### Bug Fixes

* address exact window index, report SetCVar refusal, drop duplicate binding header ([9227aff](https://github.com/AqueGen/DamageMeterCompanion/commit/9227aff94057a9736efa94af6a9b2cb4f9ee1488))
* apply final whole-branch review wave ([1e12b0a](https://github.com/AqueGen/DamageMeterCompanion/commit/1e12b0abf7e88f9dad9467d647d6fc2dac85b84d))
* close an unpinned breakdown as combat starts, so its tainted source is not compared against Secret rows ([3995b63](https://github.com/AqueGen/DamageMeterCompanion/commit/3995b6361a13adecdf684ae643e52f2dca7c97c6))
* detect silent Edit Mode refusal, close Task 8 lookup trap, document lock skip ([689e6ba](https://github.com/AqueGen/DamageMeterCompanion/commit/689e6badd6ea1978e235398d35a02b71f5a98b1b))
* drop the post-combat Refresh - it tainted Blizzard's own click handlers; probe now reports whether a fresh fetch is Secret ([ccd3bdd](https://github.com/AqueGen/DamageMeterCompanion/commit/ccd3bddf1b95e04a44ffa30e75b2551df38de83a))
* editable window sizes, live format toggle, and settings panel refresh ([d275a31](https://github.com/AqueGen/DamageMeterCompanion/commit/d275a313ae6c9f899a54560d9201784e8b3ec44d))
* fetch the meter data again when combat ends, so the numbers stop being Secret and can be formatted ([7dbf700](https://github.com/AqueGen/DamageMeterCompanion/commit/7dbf7008a19b090373c9656febb6d8df1f8bea53))
* give the left click back to Blizzard, hover only while the row's GUID is readable, and fetch again after combat so it is ([d9b7a79](https://github.com/AqueGen/DamageMeterCompanion/commit/d9b7a795ff7fc2e98fd773d9ea88c3591184b356))
* guard IsOurs, not Get, and keep the reuse branch's shown flag first ([7a4b2e0](https://github.com/AqueGen/DamageMeterCompanion/commit/7a4b2e05de273f28eea53924dfe32820615a7429))
* guard the reuse loop and migrate the snap distance default ([b8f6d51](https://github.com/AqueGen/DamageMeterCompanion/commit/b8f6d5127ad654a11549aeee8e21786d8fa3a5a7))
* honour the window lock when a size is typed in the panel ([54d6dbd](https://github.com/AqueGen/DamageMeterCompanion/commit/54d6dbd948b346023f553b32c70cd08e6c6962b3))
* hook the drag script so snapping actually writes a link ([dd38082](https://github.com/AqueGen/DamageMeterCompanion/commit/dd3808257b64aabcb8077e4c60efc4e7766e64d9))
* hover stopped working for good after one click pinned the breakdown ([b29e722](https://github.com/AqueGen/DamageMeterCompanion/commit/b29e722d1b358ac35aa35bf2c968c418066ac049))
* install every appearance hook and route menu calls through the window owner ([794410d](https://github.com/AqueGen/DamageMeterCompanion/commit/794410d308bce1442066a47bf0dc47f53ef237f4))
* keep Blizzard's window rows, clamp appearance overrides, unlink before unparenting ([8a4331f](https://github.com/AqueGen/DamageMeterCompanion/commit/8a4331ff7fc5b78e7da9df4b34bd8f978c67a1cc))
* keep preview bars inside their windows on all four snap edges ([f4d4c9b](https://github.com/AqueGen/DamageMeterCompanion/commit/f4d4c9bc3efce55af590a0210ba545279ab82d02))
* let the sweep run in combat and let issecretvalue decide, instead of refusing outright ([e2fdf37](https://github.com/AqueGen/DamageMeterCompanion/commit/e2fdf37a2d65bd7af8a22c5de90c8c4cc429a1f5))
* make extra windows creatable and detached positions stick ([f31822f](https://github.com/AqueGen/DamageMeterCompanion/commit/f31822fded32ae55b99917627d59ae8f51019361))
* never re-show a pinned source window from the hover timer ([94e6891](https://github.com/AqueGen/DamageMeterCompanion/commit/94e68913add0055779c66f7cb755aac46e061ace))
* no hooks on the meter's render path - hover, menu and idle alpha attach from one shared sweep ([55a7ece](https://github.com/AqueGen/DamageMeterCompanion/commit/55a7ece27ae3cec364f456020d663ae4ecc50cf7))
* paint numbers from our own sweep instead of hooking UpdateValue, and refuse to open settings in combat ([9c3afc0](https://github.com/AqueGen/DamageMeterCompanion/commit/9c3afc0fe63fe98094c48bc1c40bfe5da1371adf))
* paint the numbers every frame in combat so Blizzard's refresh never reaches the screen ([b49eb91](https://github.com/AqueGen/DamageMeterCompanion/commit/b49eb91ece0f62781413a1ce4e8b3455b9163fc9))
* prevent WouldCycle infinite loop on pre-existing cycle ([4c1a60e](https://github.com/AqueGen/DamageMeterCompanion/commit/4c1a60ec43e5a72c7563ddd7a0b1ad7834612c1b))
* propagate snap size down chains, respect window lock, restore position on unlink ([6ae4948](https://github.com/AqueGen/DamageMeterCompanion/commit/6ae4948d379dbcf2c878115c3b8845e0d397ba4a))
* resolve our own windows in Snap lookups ([09235b0](https://github.com/AqueGen/DamageMeterCompanion/commit/09235b0fdbe5eeaa1f854fde7e89cbaf80c2ea5f))
* resolve unrecognized strata to the default before applying it ([ab4ae88](https://github.com/AqueGen/DamageMeterCompanion/commit/ab4ae8837566d4f080bcd9a76a53d28b1e89b540))
* Settings.GetCategoryLayout does not exist, take the layout from the register call ([4a152f7](https://github.com/AqueGen/DamageMeterCompanion/commit/4a152f751636d8bd371e640ca5aa5324d03a5732))


### Reverts

* drop quick type buttons ([c4609f1](https://github.com/AqueGen/DamageMeterCompanion/commit/c4609f171a32c2cd43f49f5ab410772f54af5b47))
