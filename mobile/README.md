# Cradle of Gods Mobile

The god-sim "Cradle of Gods" as a phone-only browser game (Godot 4.7, GL
Compatibility, Web export). Touch controls, no keyboard shortcuts, lighter
rendering. Gameplay, world, villagers, religion, wildlife, powers, models,
shaders and audio are the same as the desktop game (Milestone 2).

**Status: written but never run.** Godot could not be installed where this was
built, so nothing has been imported, exported or tried on a phone. See "First
test".

## Export (Godot 4.7 editor)

1. Install export templates once: Editor > Manage Export Templates.
2. Project Manager > Import `project.godot` > Import & Edit (first import is
   slow: it builds mobile ETC2/ASTC textures).
3. Project > Export. The **Web (Mobile)** preset is included; if missing,
   Add... > Web and tick VRAM Texture Compression > For Mobile.
4. Export Project to `export/index.html` (Export With Debug off).
5. Upload the contents of `export/` to an HTTPS static host (Netlify Drop,
   itch.io HTML5, GitHub Pages) and open the link on the phone. Single-threaded
   export: no special server headers needed.
   Local check: `cd export && python3 -m http.server 8060`, then Chrome
   DevTools device mode (it generates touch events).

## Controls

| Action | Gesture |
|---|---|
| Grab / carry / throw a villager, animal, tree, rock | Touch and hold, move, lift (flick to throw) |
| Pull the world (God Hand) | Drag empty ground with one finger |
| Cast a power | Tap an icon in the bottom bar, then tap or drag on the world |
| Back to God Hand | Tap the hand icon |
| Move camera / zoom / rotate | Two fingers: drag / pinch / twist |
| Speed and pause | Time buttons, bottom right |
| Help, Fullscreen | **?** and **Full** at the top |
| Save, Load, Sound, overlays | Buttons and boxes, top left |

Landscape only: portrait shows a "turn your phone sideways" cover.
Optional URL parameter: `index.html?seed=1234` loads the same world.

## How it is built

- `scripts/touch_support.gd`: two-finger camera, ? / Full buttons, portrait cover.
- `scripts/god_hand.gd`: refreshes what is under a finger when it lands; 18 px drag threshold.
- `scripts/hud.gd`: larger tap targets, event log hidden, touch help text, no key hints.
- `scripts/main.gd`: no keyboard handling; glow off; one shadow cascade, 110 m range.
- `project.godot`: 960x540 base, `canvas_items` / `expand` scaling, MSAA off, 2048 shadow map, ETC2/ASTC, Stream audio on web.
- One finger needs no code: Godot emulates the left mouse button from the first finger.
- Saves use browser storage (`user://` = IndexedDB); per browser, lost in private tabs.

## Not identical to desktop

Simpler shadows, no glow, no anti-aliasing, no camera tilt gesture, no hover
tooltips, no event log (events still appear as toasts). World size and starting
population are unchanged, so large villages may be slow on a phone.

## First test

1. Import finishes with no script errors.
2. Tap the splash; the world appears; the whole toolbar is on screen.
3. One finger on a villager picks it up; lifting sets it down.
4. Two-finger drag / pinch / twist move the camera (if twist feels reversed,
   change `rig.yaw -= da` to `+=` in `touch_support.gd`).
5. Pick a power, tap the ground; tap the hand icon to return.
6. ? opens and closes help; Full toggles fullscreen; Save then Load works.

Known risks: HUD layout is untested and may overlap on small screens; iOS
Safari has the most WebGL/audio quirks (Android Chrome is the best target);
fullscreen is not available on iPhone (use Share > Add to Home Screen).
Audio credits: `AUDIO_CREDITS.md`.
