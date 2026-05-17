# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Calcul Mental** — a mental arithmetic training game built with Godot 4.6 (GDScript, GL Compatibility renderer). Targets Windows desktop and Android (Samsung). Ported from a Pygame prototype.

5 game modes: Contre-la-montre (timed), Série chronométrée (fixed count), Flash Anzan (flash numbers), Mode audio (TTS/STT), Calcul Infernal (n-back).

## Running and testing

There are no automated tests. All testing is manual via Godot editor:

1. Open Godot 4.3+ and import `project.godot`.
2. Press **▶ Play** (F5) to run from the main scene (`scenes/Main.tscn`).
3. Press **F6** to run the currently open scene in isolation.
4. Keyboard shortcuts during play: Enter/X = validate, Space = pause, Escape = back to menu, F11/F1 = fullscreen, Q = repeat audio.

To build an Android APK: **Project → Export → Android** in the Godot editor. Requires Android SDK Platform 34+ and OpenJDK 17 configured in Editor Settings.

## Architecture

### Autoload singletons (global, always available)

All singletons are registered in `project.godot` and load in this order:

| Singleton | File | Responsibility |
|---|---|---|
| `ThemeManager` | `scripts/autoload/theme_manager.gd` | All colors, font sizes, `StyleBoxFlat` factories, responsive `ui_scale` |
| `GameState` | `scripts/autoload/game_state.gd` | Current options dictionary, active session data, score computation |
| `ProfileManager` | `scripts/autoload/profile_manager.gd` | Named profiles saved to `user://profiles_arith.json` |
| `ScoreManager` | `scripts/autoload/score_manager.gd` | Session history + daily bests, per-profile JSON at `user://scores_arith*.json` |
| `AudioManager` | `scripts/autoload/audio_manager.gd` | SFX and music playback |
| `VoiceManager` | `scripts/autoload/voice_manager.gd` | TTS (Godot native) + STT (Android plugin or stub) |
| `SceneRouter` | `scripts/autoload/scene_router.gd` | `SceneRouter.goto("res://scenes/Foo.tscn")` — always use this, never `get_tree().change_scene_to_file` directly; handles black-fade transition |
| `CalcGenerator` | `scripts/autoload/calc_generator.gd` | Generates arithmetic expressions from `GameState.options`; returns `{expr_str, value, ...}` |

### Game mode pattern

`GameScene` (`scripts/scenes/game_scene.gd`) hosts all 5 modes with a shared UI. It instantiates the correct handler from `scripts/game_modes/` based on `GameState.options.mode` and injects itself as `mode_handler.scene`.

All mode handlers extend `ModeHandlerBase` (`scripts/game_modes/mode_base.gd`) which provides:
- `start()` — called once on game start
- `handle_submit(text)` — called when the player validates an answer
- `repeat_audio()` / `on_tts_done()` — for audio mode
- `_record_and_feedback(expr, target, user_text)` — records the answer in `GameState` and triggers visual feedback on `GameScene`

**GameScene API surface** (methods mode handlers call on `scene`):
- `show_calc(expr, hide)` — displays expression, clears input, focuses, starts timer
- `feedback(ok)` — plays SFX + visual glow/shake
- `end_session()` — navigates to `EndScene`
- `show_countdown(callable)` — 3-2-1 countdown before calling the callable

### Data flow for a game session

1. User sets options in `OptionsScene` → saved to `GameState.options` via `GameState.set_option()`
2. `GameScene._ready()` calls `GameState.reset_session()` then `_init_handler()` → mode handler `start()`
3. Handler calls `CalcGenerator.generate()` → gets `{expr_str, value, ...}` → calls `scene.show_calc()`
4. Player submits → `ModeHandlerBase._record_and_feedback()` → `GameState.record_answer()` + `scene.feedback()`
5. Session ends → `GameScene.end_session()` → `EndScene` calls `GameState.compute_final_stats()` then `ScoreManager.add_session()`

### UI construction

All UI is built **procedurally in GDScript** (no `.tscn` UI nodes — scenes contain only layout anchors). Styles always come from `ThemeManager` factories (`make_panel_style`, `make_button_style`). Font sizes use `ThemeManager.scaled_i(px)` for responsive scaling.

### Persistence

- Profiles: `user://profiles_arith.json` — `{current, profiles: {name: {options: {...}}}}`
- Scores: `user://scores_arith.json` (default profile) or `user://scores_arith_<name>.json`
- `MAX_ROWS = 800` sessions kept per profile per mode file.

## Key conventions

- All navigation goes through `SceneRouter.goto()`, never direct scene changes.
- All visual styling (colors, radii, font sizes) comes from `ThemeManager` constants — no hardcoded color values elsewhere.
- `CalcGenerator.generate()` tries up to 50 times to satisfy constraints, then falls back to a simple 1-digit addition. Constraint changes must be validated in `_validate()`.
- `_evaluate()` in `CalcGenerator` uses operator precedence (× ÷ before + −), not left-to-right. Keep this consistent with `_build_expr()` display.
- The STT feature is a stub on PC (`VoiceManager` checks for an Android plugin at runtime). Audio mode and voice input degrade silently if unavailable — no errors thrown.
