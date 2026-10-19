# Changelog

## 0.1.0 (Unreleased)

- Initialized ForeverCDMAdvanced from ForeverCDM 0.8.0.
- Replaced the four static rows with profile-owned dynamic named bars.
- Added per-bar grids, icon size, spacing, horizontal growth and vertical growth.
- Replaced Spellbook checkboxes with drag-and-drop and selected-bar adding.
- Added per-entry cooldown, aura, debuff, aura+cooldown and reactive modes.
- Added per-entry ready/inactive visibility, duration overrides and generalized
  Combine groups.
- Added Riposte and Surprise Attack proc windows. A used reactive ability remains
  visible for its actual cooldown and hides on `OnCooldownDone`.
- Added secret-safe cooldown, charge and aura duration-object handling.
- Added per-bar EllesmereUI border sync with solid and borderless alternatives.
- Added configurable static proc glow with OctoCooldowns ready/blocked states.
- Added per-bar timer/count font face, size and outline controls.
- Added a separate Appearance panel with colour pickers.
- Made complete bar collections and layout profile-owned.
- Introduced schema v2 with an intentional full reset of the old static format.
- Removed the settings macro mirror.

## Upstream History

Changes made before this project was created are documented in the
[ForeverCDM changelog](https://github.com/Thunderz96/ForeverCDM/blob/main/CHANGELOG.md).
