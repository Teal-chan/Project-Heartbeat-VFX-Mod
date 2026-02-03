
<img width="189" height="208" alt="scale" src="https://github.com/user-attachments/assets/629e8d95-0b73-4d3b-a8ec-a1533977b883" />
<img width="165" height="201" alt="color" src="https://github.com/user-attachments/assets/c738a7fa-f767-416a-80e3-c31c74a2280f" />
<img width="231" height="249" alt="rotation" src="https://github.com/user-attachments/assets/6ecd2711-e891-4858-aa15-5021399affcf" />
<img width="212" height="313" alt="offset" src="https://github.com/user-attachments/assets/e5205a1a-0903-45dc-9b8a-46ccf62df6ff" />
<img width="245" height="280" alt="glow" src="https://github.com/user-attachments/assets/ae5a4050-0a62-4a96-a124-fd02f7bc81b9" />
<img width="542" height="337" alt="spotlight" src="https://github.com/user-attachments/assets/99208c28-dfc3-49ca-9dde-d12822d3ce10" />
<img width="252" height="200" alt="field slide" src="https://github.com/user-attachments/assets/30abee88-1c35-4fd0-9cc0-31f3442e5d56" />
<img width="314" height="264" alt="field rotation" src="https://github.com/user-attachments/assets/826e6f9d-ffee-4616-b53e-a4c54c3b5c30" />
<img width="358" height="311" alt="field scale" src="https://github.com/user-attachments/assets/194d37e7-e777-418a-a1a3-4f80330fa5ba" />

<img width="839" height="475" alt="Screenshot 2025-11-03 095214" src="https://github.com/user-attachments/assets/72143b95-d6b1-4c92-a137-720ff5631873" />
<img width="1897" height="611" alt="Screenshot 2026-02-03 014628" src="https://github.com/user-attachments/assets/a508a9f5-dc83-488e-a0de-cda96ab7d0f7" />

# Project Heartbeat Advanced Mode

A comprehensive modding framework for [Project Heartbeat](https://store.steampowered.com/app/1216230/Project_Heartbeat/) that adds professional-grade VFX authoring, quality-of-life editor improvements, and new gameplay features.

Created by **An Idol in Teal** (Josh), with assistance from AI tools.

---

## ✨ Features Overview

### 🎨 VFX Modcharting System
A complete visual effects authoring suite that rivals Project Diva's modchart capabilities:

- **Per-note effects**: Scale, Color, Rotation, Offset, Glow
- **Spotlight system**: Dramatic focus effects that follow notes
- **Field VFX**: Playfield-wide slides, rotation, and zoom
- **Mirai-style link lines**: Connect notes visually like Project Mirai
- **Real-time preview**: See effects as you author them
- **Leaderboard legal**: All VFX are purely cosmetic—scores still count! (This is a back end modification to 'whitelist' certain modifiers.)

### 🛠️ Editor Enhancements
Quality-of-life improvements that streamline the charting workflow:

- **Quick-access toolbar buttons**: Edit Song Data, Verify Chart, Upload to Workshop
- **Inspector calculated info**: See timeout, duration, hit count, and score for Rush notes
- **Bookmarks system**: Annotate your charts with timestamped notes
- **Icon pack switcher**: Change note icons without leaving the editor
- **Open in external editor**: Quick access to chart JSON files
- **Plus dozens more** (Playhead controls, selection utilities, VFX Inspector and Summary, etc.)

### 🎮 New Gameplay Features
- **Perfect Run modifier**: Fail on any non-passing hit, with optional FINE limits
- **VFX indicators**: See which songs have VFX before playing

---

## 📦 Installation

> **Note**: This mod requires a legally purchased copy of Project Heartbeat. Please purchase the game on Steam if you want to play the mod.

1. Browse your Local Files, find the "Project Heartbeat.pck" file, make a copy and back it up
2. Replace it with the modded version here: https://drive.google.com/file/d/1NYS_pxKe2lU-Dd8PU7a5x7Ok3VQZsJsZ/view?usp=sharing
3. Place the current version of the VFX Scripts into your editor_scripts folder (from Tools/Open User Directory in the game): https://drive.google.com/file/d/15SBMQrnqf7ec3Vr2Ga9dyulJdyZOOi4Z/view?usp=sharing
3. Launch the game normally (Or preferably, from command prompt/terminal to see the console outputs)

### File Structure
```
Project Heartbeat/
├── rythm_game/
│   └── modifiers/
│       ├── ph_vfx/           # VFX runtime modifier
│       └── perfect_run/       # Perfect Run modifier
├── tools/
│   └── editor/
│       ├── Editor.gd          # Modded editor with toolbar buttons
│       ├── Editor.tscn
│       ├── EditorInspector.gd # Enhanced inspector
│       └── WorkshopUploadForm.gd  # VFX upload support
├── menus/
│   ├── song_list/
│   │   └── SongListItem.gd    # VFX indicator
│   ├── workshop_browser/
│   │   └── WorkshopItemThumbnail.gd  # Workshop VFX badge
│   └── pregame_screen/
│       └── PreGameScreen.gd   # VFX context bridge
└── user://editor_scripts/     # VFX authoring modules (created on first run)
```

---

## 🎨 VFX System Guide

### Getting Started

1. Open the editor and load a chart
2. Launch 'Install VFX Toolbox' script
3. The VFX modules appear in the left panel under their respective tabs
4. Select notes in the timeline, then configure effects in the module panels
5. Effects preview in real-time as you scrub the timeline

### Available Effect Types

| Module | Description | Parameters |
|--------|-------------|------------|
| **Scale** | Resize note components | Per-part scale factors (head, tail, target, etc.) |
| **Color** | Tint and fade notes | RGBA color with alpha for transparency |
| **Rotation** | Spin note components | Degrees with easing curves |
| **Offset** | Move notes from default position | X/Y pixel offset |
| **Glow** | Add bloom/glow effect | Intensity value |
| **Spotlight** | Screen-space focus effect | Radius, feather, tint, priority |
| **Field VFX** | Playfield transforms | Slide position, rotation, zoom with pivots |

### Keyframe System

Effects use a keyframe-based animation system:

```
Time: 1000ms → 2000ms
Scale: 1.0 → 2.0 (ease: quad_out)
```

- **Start/End times**: When the effect begins and ends
- **Start/End values**: The interpolated range
- **Easing**: Animation curve (hold/step, linear, quad_in, quad_out, quad_in_out, cubic_in_out)

### Hold End System and Note Calculation

Effects can end on note impact, or continue until the note's visibility actually ends (Sustain/Rush notes.) This is specifically designed with Rush notes in mind, but Sustain notes work just as well.

The modified Editor Inspector calculates the duration of sustain and rush notes for this purpose. This feature will eventually be implemented to the base game!

### Inheritance System

Effects cascade through a hierarchy:

```
$GLOBAL → $ALL_NOTES → $UP (note type) → layer_UP@0@12500 (specific note)
```

- Leave a field blank to inherit from the parent level
- Override only what you need to change
- `$GLOBAL` affects everything, specific note keys affect only that note

### Field VFX

Field effects transform the entire playfield:

- **Slides**: Move the playfield to authored positions
- **Rotation**: Spin around a configurable pivot point
- **Scale/Zoom**: Enlarge or shrink around a pivot

The JudgementLabel (COOL/FINE/SAD text) automatically follows field transforms.

If desired, the UserUI (Song title, progress bar, accuracy indicator) can also be transformed in the same manner as the playfield.

### Exporting & Distribution

VFX data is saved as JSON files alongside your charts:

```
user://editor_songs/my_song/
├── hard.json          # Chart data
├── hard_vfx.json      # VFX data (auto-generated)
└── preview.png
```

When uploading to Steam Workshop:
1. Check "Include VFX file" in the upload dialog
2. VFX files are bundled with your song
3. Workshop listing shows "★ VFX" badge
4. Downloaders automatically get VFX support

---

## 🏃 Perfect Run Modifier

A challenge modifier for players seeking perfection.

### Modes

| Mode | Behavior |
|------|----------|
| **Standard** | Fail on SAFE, SAD, WORST or WRONG |
| **COOL Only** | Fail on anything except COOL |
| **FINE Limit** | Allow N FINEs before failing |

### FINE Counter

A togglable on-screen counter displays:
- Current FINE count
- If using FINE Limit, color changes as you approach the limit (white → yellow → red)

### Leaderboard Legal

Perfect Run only makes the game harder, so scores are fully leaderboard-eligible.

---

## 📑 Bookmarks System

Add notes and markers to your charts for organization.

### Features

- **Timestamped notes**: Mark sections with descriptions
- **Color coding**: Customize bookmark colors for categorization
- **Quick navigation**: Jump between bookmarks with Prev/Next buttons
- **Timeline markers**: Visual lines on the timeline at bookmark positions
- **Per-chart storage**: Bookmarks are saved alongside your chart files

### Usage

1. Position the playhead where you want a bookmark
2. Enter a note in the text field
3. Click "Add / Update at Playhead"
4. Use "< Prev" and "Next >" to navigate between bookmarks

---

## 🔧 Editor Toolbar Additions

New buttons added to the editor's top bar:

| Button | Function |
|--------|----------|
| 📝 | Edit Song Data for current song |
| ✓ | Verify current chart |
| ⬆️ | Upload to Steam Workshop |
| 📁 | Open chart JSON in external editor |
| 🎨 | Select icon pack |

These functions were previously buried in the Open Chart dialog—now they're one click away.

---

## 📊 Inspector Enhancements

The note inspector now shows calculated values:

### For All Notes
- **Timeout**: How long until the note expires (accounts for note speed changes)

### For Sustain Notes
- **Duration**: Length in milliseconds

### For Rush Notes
- **Duration**: Length in milliseconds
- **Hit Count**: Number of hits required
- **Score**: Total points from the rush note

Values update in real-time as you edit note properties.

---

## 🎯 Technical Details

### Architecture

The VFX system consists of several interconnected components:

```
Authoring (Editor)
    ↓
Seven VFX Modules → VFXUtils → JSON Files
    ↓
Preview (Editor)
    ↓
MegaInjector → AnimBank → Shaders
    ↓
Runtime (Game)
    ↓
ph_vfx.gd Modifier → Same AnimBank/Shaders
```

### Performance Optimizations

- **Bucketed animation data**: O(log n) keyframe lookup via binary search
- **Per-frame sampling cache**: Same note sampled once even if multiple drawers
- **Event cursor system**: O(1) amortized event tracking
- **Deferred transform commit**: Batch scale+rotation+offset into single shader update
- **Throttled heavy updates**: Spotlight overlay updates every other frame

### Shader System

Custom shaders handle visual transforms:

- **note_vfx.gdshader**: 4-in-1 shader for scale, rotation, offset, and color
- **spot_overlay.gdshader**: Screen-space vignette for spotlight effects

All transforms are GPU-accelerated with proper pivot handling.

---

## 🤝 Contributing

This project exists thanks to the openness of EirTeam in making Project Heartbeat's source available.

### Planned Features

- Bezier curve support for Offset, Mirai Link and possibly Field Slide
- YouTube tutorial series

### Reporting Issues

Please include:
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output
- Chart/VFX files if applicable

---

## 📜 Credits

- **An Idol in Teal (Josh)** — Primary developer
- **EirTeam / Lino** — Project Heartbeat developers, guidance on editor internals
- **Claude (Anthropic)** — Development assistance
- **ChatGPT (OpenAI)** — Early development assistance
- **Project Heartbeat Community** — Feature requests and testing

---

## 📄 License

This mod is provided for use with legally obtained copies of Project Heartbeat. The VFX system and editor enhancements are original work by An Idol in Teal.

The file is provided under the MIT License for permissive responsibility.

Project Heartbeat is developed by EirTeam. This mod is not officially affiliated with or endorsed by EirTeam, though some features may be incorporated into future official releases.

---

## 🔗 Links

- [Project Heartbeat on Steam](https://store.steampowered.com/app/1216230/Project_Heartbeat/)
- [Project Heartbeat Homepage](https://ph.eirteam.moe)
- [Community Charting Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=2465841098)

---

*"I don't want a sanitized UI that everyone has access to. I want to show that I've been working under the hood to make the charts look like something on another level." — Teal*
