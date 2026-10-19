# ForeverCDMAdvanced

<img src=".github/logo.png" width="128" align="right" alt="Forever CDM Advanced logo">

A dynamic cooldown and aura manager for **World of Warcraft: Forever**. It does
not depend on authored Blizzard Cooldown Manager data.

**Maintainer:** hneis · **Original author:** Thunderz · **Version:** 0.1.0 ·
**Interface:** 16001

ForeverCDMAdvanced is based on
[ForeverCDM](https://github.com/Thunderz96/ForeverCDM) and retains its MIT
license. Its addon namespace, SavedVariables and `/fcdma` command are separate.

## Dynamic bars

A new profile starts with no bars. Open `/fcdma` and choose **Create Bar**. Each
profile owns its complete bar collection, including:

- bar names and ordering;
- icon size and spacing;
- fixed row and column capacity;
- horizontal growth to the left or right;
- vertical growth up or down;
- positions and anchors;
- entries, modes and Combine groups.

The grid has a hard `rows × columns` capacity. Hidden and unavailable entries
are packed without gaps, but they still occupy configured slots. Combine members
share one slot.

Bars can be unlocked and dragged. In Edit Mode, right-click a bar handle to
attach it to another ForeverCDMAdvanced bar or a visible Blizzard Edit Mode
frame. Positions and anchors are stored in the active profile.

## Adding entries

The custom Spellbook remains in `/fcdma`, but it no longer contains one checkbox
per static bar. Select a bar and either:

- drag a Spellbook row into the selected bar;
- click **Add** on a Spellbook row;
- enter a spell name, spell ID, `item:1234`, or an item link.

Changing talents does not remove configured entries. A spell unavailable in the
current build is hidden while bars are locked and returns when it becomes
available again.

## Entry modes

Every entry chooses its own tracking mode, so one bar may mix all of these:

| Mode | Behaviour |
| --- | --- |
| `cooldown` | Spell or item cooldown, charges and item count |
| `aura` | Player aura only |
| `debuff` | Your debuff on the current target |
| `auraCooldown` | Active aura, then spell cooldown, then configurable ready state |
| `reactive` | Hidden condition window followed by cooldown after use |

Ready visibility can be `always`, `combat`, or `hide`. Inactive auras can stay
dimmed or be hidden. Items always use `cooldown` mode.

**Combine with previous** puts several entries in one visual slot. Each member
keeps its own mode and duration settings. Combine is manual: do not combine
abilities that must be visible simultaneously.

## Reactive abilities

Riposte and Surprise Attack are recognised in English and Russian.

Riposte uses this lifecycle:

1. Hidden while no parry window exists.
2. Appears after a parry with a four-second proc timer.
3. When used, switches from the proc timer to the actual spell cooldown.
4. Hides again when the cooldown widget reports completion.

If another proc occurs while the ability is on cooldown, the bar can show it
with a red state or hide it. Surprise Attack is additionally bound to the target
that dodged.

The four-second value is a catalog default and can be overridden per entry.

## Durations and secret values

Duration sources are used in this order:

1. Live aura/cooldown data or a Blizzard duration object.
2. Manual per-entry duration.
3. A duration previously learned from readable aura data.
4. A verified catalog default.

Secret cooldown and aura values are never compared or formatted in Lua. They are
passed directly to `CooldownFrameTemplate`. Reactive cooldown completion uses
the widget's `OnCooldownDone` callback.

## Profiles and reset

Characters are mapped to named profiles by GUID. **New** creates an empty
zero-bar profile, **Copy** deep-copies all bars and layout, and **Rename** keeps
characters sharing the profile attached to it.

Schema v2 intentionally does not migrate the former static `CD`, `UTIL`, `BUFF`
and `DEBUFF` rows. Loading an older database creates a clean zero-bar profile.
`/fcdma reset` performs the same full reset for all addon profiles.

Macro backup has been removed. The addon relies only on SavedVariables, even on
Forever builds where the client may fail to restore them after a cold restart.

## Commands

`/fcdma` opens the settings window. `/fcdma help` prints the current command
list. Common commands are:

```text
/fcdma bar new <name>
/fcdma bar list
/fcdma add <barID> <spell or item>
/fcdma mode <barID> <entry> <cooldown|aura|debuff|auraCooldown|reactive>
/fcdma grid <barID> <rows> <columns>
/fcdma grow <barID> <left|right> <up|down>
/fcdma anchor <barID> <otherBarID|FrameName|none>
/fcdma duration <barID> <entry> <seconds|auto>
/fcdma lock
/fcdma unlock
```

## Development

Run the Lua 5.1 syntax checks and integration test from the addon directory:

```bash
luac5.1 -p ForeverCDMAdvanced.lua
luac5.1 -p ForeverCDMAdvanced_UI.lua
lua tests/test_dynamic.lua
../tools/validate-addon.sh ForeverCDMAdvanced
```

The integration test covers schema reset, profiles, dynamic grid layout, hard
capacity, Combine, all entry modes, secret durations, reactive cooldown latching
and the zero-bar UI.

MIT.
