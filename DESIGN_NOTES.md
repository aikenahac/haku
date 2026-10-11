# Design notes

This log covers gaps, ambiguities, and decisions I made where `design/` was silent or contradicted itself. `design/` stays the source of truth, and every entry here takes the closest option that stays consistent with it.

## Product decisions (agreed 2026-10-10)

| Topic | Decision |
|---|---|
| Wake word | It ships in v3 and is **on by default**. Onboarding step 2 ("Nothing listens in the background") and the Voice settings copy will change in v3 to say Haku listens on-device for its name, with an off switch. Until v3, the current copy is accurate. |
| Accessibility reading | Haku reads only `{selection}`, `{front app}` and `{clipboard}`. There's no general "what's this?" window reading. Onboarding step 4 copy changes to "lets the hotkey work everywhere and lets workflows use your selection and front app." |
| Widget gestures | Press and hold the widget, or hold ⌥Space, to talk. A click toggles the expanded panel. Right-click opens the menu. Dropping a file or image on the widget attaches it. |
| Workflows | Each workflow has one action (Ask model / Shell / Script / Agent), as in the editor mockup. Multi-step chains are deferred. |

## Wake word (built 2026-10-10)

- **On by default**, as agreed. Onboarding step 2 now says Haku listens when you hold the hotkey, when a prompt waits for an answer, and for its name, all on this Mac. The switch is at Settings › Hotkeys & voice › Listen for “Haku”, with a status line, a sensitivity slider and the wake-model state.
- **Two detectors:**
  - A custom openWakeWord model run through ONNX Runtime, used when `~/Library/Application Support/Haku/wakeword/{melspectrogram,embedding_model,haku}.onnx` exist. Train it with `tools/wakeword/train_haku.sh`.
  - Until then, continuous on-device SpeechAnalyzer transcription matching “Haku” and common mishearings.
  - The sensitivity slider only affects the custom model.
- **Detection pauses** while you hold to talk, while Haku speaks, and while a slip is waiting, so Haku doesn't wake itself.
- **After the wake word:**
  - Two or more words in the same breath (“Haku, open notes”) are sent straight away.
  - Otherwise a soft “Tink” plays and Haku listens hands-free, stopping after about 1.3 s of silence. If nothing is said within 6 s it gives up.
- **Visual:** the design has no state for wake listening, so the widget stays in its idle state. The macOS mic indicator shows while name listening is on.

## Main window (built 2026-10-11, not in the mockups)

- **Built from existing Margin parts only:**
  - Sidebar: wordmark, chats grouped Pinned / Today / Yesterday / Previous 7 days / Earlier, search, and Tasks / Workflows / Settings nav items in the Settings-nav style.
  - The selected chat is marked with the `marginLine` rule.
  - Chat view: the panel's conversation, margin and input, capped at 860 pt wide.
  - Tasks, Workflows and Settings render embedded, without their own close buttons.
- **Conversations:** the widget, panel and window share the current chat. A new chat starts after 2 h idle or on ⌘N. Titles start from the first message and are then refined by Gemma.
- **Dock:** "Show in Dock" is on by default. Turning it off makes Haku a menu-bar-and-widget-only app again.

## Tokens

- **Single source:** `tools/design-tokens/colors.json` → `generate_assets.py` → `Haku/Resources/Colors.xcassets`. Don't edit the catalog by hand.
- **Daylight and Carbon** are the two appearances of one Margin theme: one color set each, with Any and Dark variants. In the theme grid, picking Daylight sets Mode to Light and picking Carbon sets it to Dark. "Match system" switches between the two.
- **Extra themes have a fixed appearance:** Blueprint is dark and Legal pad, Typewriter and Kraft are light. The Mode control only affects Daylight and Carbon.
- **Highlighter color setting** applies only to Daylight and Carbon. Each extra theme keeps its own marking: the Blueprint dashed box, Legal pad pink `#F29BB4`, Typewriter ribbon `#B3261E`, and Kraft chalk `#F7F1E3`.
- **Settings theme-grid swatches** differ from the tokens in two places: Carbon shows `#E2C13B` (token is `#F4D24C`) and Blueprint shows `#F2E7C4`. I treat these as thumbnail colors and use the tokens.
- **Values the design doesn't give, so I derived them.** Each one passes 4.5:1, enforced by `ContrastTests`:
  - Blueprint `paper2` is `#163F68`, darker than the paper so the muted `#B9CDE2` text still passes. My first pick, the settings edge `#2C6196`, only reached 3.96:1.
  - Blueprint `error` is `#FFB4A8`, because `#B3261E` is unreadable on blue.
  - Kraft `error` is `#7E1A12`, because `#B3261E` only reaches about 3.9:1 on `#D2B88F`.
  - `paper2` for Legal pad, Typewriter and Kraft is each theme's backdrop color: `#FBF0B2`, `#F3F0E8` and `#C2A47B`.
  - `blueInk`, used for links and "running": Legal pad uses `#24467A` as specified. Blueprint, Typewriter and Kraft use their ink, because their margin notes are drawn in ink in the mockups.
  - Blueprint rules are ink at 28%, and its grid is ink at 8%.
- **Shadow spread:** the paper shadow (`0 8 18 −10`) has a negative spread, which SwiftUI's `.shadow` can't express. `PaperBackground` draws each layer as an inset, offset, blurred copy of the shape, with blur radius = CSS blur ÷ 2.
- **Typewriter and Blueprint have no shadow,** because the mockups draw none.

## Type

- **Blueprint:** HANDOFF says "everything IBM Plex Mono uppercase", but the Themes mockup sets Haku's conversation lines in serif, and only the chrome (state words, labels, header, user lines) in mono uppercase. I followed the mockup.
- **Typewriter** uses Courier Prime everywhere, and its chrome is lowercase ("haku", "claude code", "opt+space").
- **Widget state size per theme,** from the mockups: Blueprint is 11/17 of the Margin size and Typewriter is 14/17. Legal pad and Kraft keep the Margin size, because their 44 pt thumbnails are scaled-down samples.
- **Small caps tracking** is 0.07em. The mockups vary between 0.06 and 0.08, and HANDOFF says +0.07.

## Highlighter

- The highlighter is drawn with a `TextRenderer` (`InkTextRenderer`), so marks work both inside a paragraph and on single words.
- **Band position:** the band is measured against the run's typographic bounds (ascent + descent). That matches how CSS paints an inline span's background over its content area, not the line box.
- **Bands per theme:** Margin light 52–92%, Legal pad 50–92%, Kraft chalk 45–88%, wordmark 55–88%. Carbon uses a full fill with `#1C1E24` text.

## Widget

- **Seal states** (only idle is drawn in the design):
  - listening: "h" with the highlighter plus a small squiggle
  - thinking: three dots in place of the "h"
  - speaking: "h" with the hand underline
  - agent running: "h" plus the stamp badge
  - error: red ring and a wavy "h"
- **Index tab:** its body uses the slip's size metrics, and the 60×16 tab sits on top, overlapping by 2 pt. Like the mockup, it shows no glyph.
- **Extra themes:** the mockups draw only idle, listening and agent running. Thinking, speaking and error use the Margin layout with each theme's fonts, colors and marking. Extra themes show no glyph, as in the mockups.
- **Running-jobs stamp** appears as an overlay in every theme except Kraft, which shows it inline instead of a tally. The Blueprint stamp is square.
- **Agent progress per theme:**
  - Margin: tally, then `2/5`
  - Blueprint: `2/5`, then square cells, with the current cell dashed
  - Legal pad: blue tally with no count
  - Typewriter: `[##-–]`, with the current step `#` in ribbon red
  - Kraft: stamp
- **Listening amplitude:** the mic level scales the squiggle's amplitude between 35% and 100%, and the stroke-trim redraw loops on top. With Reduce Motion on, both stop and the full static squiggle shows.
- **Typewriter listening:** the timer counts from when listening started, and the cursor blinks at 1 Hz (static under Reduce Motion).
- **Idle animation:** HANDOFF calls it optional and off by default, but never draws it. The setting is stored, and the animation is deferred until there's a design for it.
- **S and L sizes:** the design specifies only the widget dimensions. I scaled the rest from M: S uses glyph 14 / text 14 and L uses glyph 22 / text 21 (both from the Size sample), and the trailing elements scale proportionally.

## Panel

- **Textures** (Blueprint grid, Legal pad rules, Kraft speckle) appear only on the mockup backdrops. A real desktop has no backdrop, so I apply each texture to the panel and window surfaces. The widget stays plain for legibility.
- **Legal pad ruled lines** follow a fixed 28 pt pitch, while body text uses the density line height, so the two aren't baseline-locked.
- **Legal pad margin:** the CSS draws a 2 pt border plus a −2 pt-spread box-shadow, which renders as a single 4 pt bar. I read the intent as the usual double red line and draw two 1 pt lines 2 pt apart.
- **Extra-theme panels** in the mockups are 300 pt-tall thumbnails. Each one keeps the 460×640 Margin layout and uses its own:
  - header date format (Typewriter `dd.MM.yy`)
  - user-line prefix (`—` / `›` / `>`)
  - placeholder copy
  - mic button (round / square / `[mic]`)
  - rule style (Typewriter dashed)
- **Margin notes** line up with the message that started the job, because each message row carries its own margin cell.
- **Density:** Comfortable is the panel mockup (16 pt, 1.45 line height, 18 gap). Compact is the density sample (14 pt, 1.3 line height, 4 gap).

## Open

- **Hotkeys:** hold-to-talk now defaults to **⌃⌥Space** (changed 2026-10-10 at your request; ⌥Space clashes with common launchers). Existing installs on the old ⌥Space default are migrated once; custom shortcuts are kept. The widget hint and input placeholder read the live shortcut, written per theme (⌃⌥ SPACE / ⌃⌥ SPC / ctrl+opt+space). Open panel ⌥⇧Space and Tasks ⌥⇧T are unchanged.
- **Voice confirmations** only accept a short yes/no phrase (at most 3 words, from a fixed list, held steady for 0.5 s). Talking in the background can never approve a slip. Every approve/deny is logged with its source in `~/Library/Application Support/Haku/haku.log`.
- **App icon:** the vector is in place (`AppIconView`). Exporting the PNG `.appiconset` and the template menu-bar images happens in v0b, together with the status item.
