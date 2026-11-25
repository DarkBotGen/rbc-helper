# RBC Helper

Standalone Bee Swarm Simulator Robo Bear Challenge & field utility built with the Atlas+ UI.

## Features

- **Golden Cogmower Monitor:** Top-of-screen HUD showing whether any `Gold Cogmower` is on the map and which field it is in, with optional spawn notifications
- **Atlas+ WalkSpeed:** Fixed and dynamic walkspeed modes up to `90` while preserving external boosts
- **Hide Decorations:** Reversible World / Performance toggle matching `fullscript.txt` decoration targets cleanly restoring parents and platform collision on disable/unload
- **Auto Face Flames (`BodyGyro`):** Shift Lock–compatible (`Humanoid.AutoRotate` suppression + post-camera `BindToRenderStep`) Y-axis yaw facing (`MaxTorque = (0, inf, 0)`) that never locks your camera or overrides movement, prioritizes expiring flames for refresh, cleanly restores `AutoRotate`, and includes optional refresh-synced auto dig
- **Digital Smiley Duped Token Highlighter & Timer:** Clean contour `Highlight` (`FillTransparency = 0.58`), sleek upright `Cylinder` ground drop beam + `CylinderHandleAdornment` X-ray, and live countdown `BillboardGui` with integrated progress bar ticking from Green to Yellow/Orange and snapping to solid Red (`TOO LATE`) under `0.9s`

## Loadstring (Once Published to `DarkBotGen/rbc-helper`)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/rbc-helper/main/loader.lua"))()
```

> **Performance & FPS Optimizer (`World / Performance`) & Clean UI**:
> - One-click **Ultra FPS Mode (Preset)** toggles extreme potato/anti-lag optimizations together (Low Graphics + Clouds off, Hide Decorations, Hide Bees, Hide Players, Hide Flowers, Hide Field Balloons, and strict `ULTRA_ALLOWED_LOCAL_FX` filtering)
> - Reversible **Low Graphics / Anti-Lag** (disables shadows, fog, IBL specular/diffuse, Atmosphere haze, `Clouds`, post-effects, water ripples, terrain grass, `PollenPopUps`, sets `Level01`, simplifies non-`Neon`/`Glass`/`ForceField` world parts while preserving `LocalPlayer.Character` and highlight/drop beams without hot `workspace.DescendantAdded` overhead)
> - Reversible **Hide Bees**, **Hide Other Players**, **Hide Flowers**, **Hide Field Balloons**, and **Filter Particles (Keep Key FX)** (preserves `LocalFlames`, `Precise Shot`, `PrecisionPopUp`, `CogSawProjectile`, `Bubble`, star/coconut VFX, `StickerTokenBeam`)
> - Zero-VRAM chevron icons, modern pill switches, scale-based sliders with zero drag tweens, slim HUD/toasts, debounced event-driven `goldCogMonitor`, weak `savedParticles` cleanup, 20Hz `smileyHighlighter` HUD throttle (with immediate `< 0.9s` red flip), and Shift Lock–compatible `flameController` target caching

> Offline compilation, static analysis, unit tests, and headless E2E checks pass. Live in-game Roblox behavior has not been verified yet.
