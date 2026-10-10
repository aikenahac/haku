# Haku — design handoff

Direction: **Margin** (paper & ink). Haku feels like a slip of paper on your desk. It talks in a serif italic, marks what matters with a highlighter, and keeps agent jobs as notes in the margin.

This folder is the source of truth for the look of the app. The mockups are HTML, not SwiftUI. Read them for layout, sizes, copy and states, then rebuild natively. Don't port the HTML or CSS line by line.

## Files

| File | What's in it |
|---|---|
| `mockups/Margin-Widget-Panel.dc.html` | Logo/wordmark, app icons, menu-bar glyph, the 6 widget states, expanded panel. Light + dark. |
| `mockups/Margin-Tasks.dc.html` | Tasks window: running job (light), finished job (dark). |
| `mockups/Margin-Confirm.dc.html` | Confirmation prompts: shell command, script, agent delegation. |
| `mockups/Margin-Workflows.dc.html` | Workflows editor. |
| `mockups/Margin-Settings.dc.html` | Settings: models & agents, hotkeys & voice, appearance. |
| `mockups/Margin-Onboarding.dc.html` | 5-step permissions flow. |
| `mockups/Margin-Themes.dc.html` | 4 extra themes + widget shape/size/opacity/density options. |
| `mockups/explorations/` | The two rejected directions (Signal, Kiln). Reference only — don't build. |

How to read a mockup: the markup sits inside `<x-dc>`. `{{name}}` is a template hole filled from `renderVals()` in the `<script type="text/x-dc">` block at the bottom. `<sc-for>` repeats, `<sc-if>` branches. Colors come from the CSS variables on `.light` and `.dark` in each file's `<style>`. The files won't render in a plain browser because they need the canvas runtime. Use the PNG exports next to them (if present) to see what they look like.

## Tokens

### Color — base themes

| Token | Light ("Daylight") | Dark ("Carbon") | Use |
|---|---|---|---|
| `desk` | `#E6E1D4` | `#111215` | Preview backdrop only (stands in for the desktop) |
| `paper` | `#FCFAF4` | `#1D1E22` | Widget, panel and window surface |
| `paper2` | `#F3EFE4` | `#26272C` | Input wells, selected rows, code/log blocks |
| `ink` | `#1C1E24` | `#ECE8DD` | Primary text, primary buttons (filled), icons |
| `muted` | `#5A5C63` | `#A8A498` | Labels, secondary text (passes 4.5:1 on paper) |
| `rule` | `#DAD3C3` | `#36373D` | Borders, dividers, inactive tally strokes |
| `blueInk` | `#24467A` | `#A3BCE6` | Links, margin notes, "running" status |
| `marginLine` | `#E2B4AC` | `#5A3A38` | Vertical margin rule in the panel |
| `error` | `#B3261E` | `#FF8F7F` | Errors, destructive warnings (always with wavy underline or text, never color alone) |
| `highlight` | `#F4D24C` | `#F4D24C` | Highlighter. User-selectable: `#F4D24C` `#9FE0B4` `#F7A9BE` `#9CC8F2` |

Highlighter rule: in light mode it's a band behind the lower ~40% of the text (52%–92% of line height). In dark mode it's a full fill behind the text, and the text stays `#1C1E24` so contrast holds.

### Extra themes (texture changes, not just recolors)

| Theme | Paper | Ink | Muted | Accent / marking | Texture & type |
|---|---|---|---|---|---|
| Blueprint | `#1B4A78` | `#EAF2FA` | `#B9CDE2` | Dashed outline box instead of highlighter | 16 px grid at 8% white; everything IBM Plex Mono uppercase, square corners, 1 px ink borders; progress as square cells |
| Legal pad | `#FBF0B2` (surface `#FDF5C9`) | `#1E2A44` | `#4B5570` | Pink highlighter `#F29BB4`; blue ink `#24467A` | 28 px ruled lines `#A9C6E2`, red double margin `#E07B7B`, oxblood binding strip `#7A2E2E` on top of widget/panel |
| Typewriter | `#F3F0E8` (surface `#FBFAF5`) | `#16161A` | `#4F4F55` | Red ribbon text `#B3261E` instead of a fill | All Courier Prime; dashed rules; block cursor while listening; progress as `[##---]` |
| Kraft | `#C2A47B` (surface `#D2B88F`) | `#271D13` | `#46372A` | White chalk band `#F7F1E3` | Speckle texture; widget is a shipping tag (punched hole on the left, rounded right end); stamp-style count badge |

### Type

| Role | Font | Notes |
|---|---|---|
| Haku's voice, state words, headings, labels | **Newsreader** (italic for state words and labels) | Variable, opsz 6–72. Bundle it. |
| UI text, buttons, small caps labels | **Atkinson Hyperlegible** | Small caps = 10.5–11 pt, uppercase, +0.07em tracking |
| Paths, logs, code, shortcuts | **IBM Plex Mono** | 11–12.5 pt |
| Typewriter theme only | **Courier Prime** | |

All four are OFL (Courier Prime too), so they can ship inside the app. Fallbacks: New York, SF Pro, SF Mono.

Sizes used: wordmark 96, window titles 22, task title 24, onboarding titles 24, panel body serif 16, list items serif 15, labels 13–14, small caps 10.5–11.

### Shape & spacing

- Widget: radius 3, 1 px `rule` border, paper shadow (`0 1 0 /6%`, `0 8 18 -10 /40%`, warm brown in light, black in dark).
- Panel/windows: radius 4. Buttons radius 3. No pill shapes in this direction except the seal widget.
- Spacing on a 2/4 px base. Usual gaps: 6, 8, 10, 14, 18. Window padding 18–22.

## Logo

An index card with a tab on the top-left, filled ink, with a slightly tilted (−3°) highlighter stroke across it and a short paper-colored line below. The wordmark is "Haku" in Newsreader italic 500, with the highlighter behind "ku". The menu-bar glyph is the card silhouette: outline when idle, filled when active. Make it a template image so macOS tints it. The exact SVG paths are in `Margin-Widget-Panel.dc.html` (viewBox 48).

## Floating widget

Size M = 252×46 (S = 200×36, L = 300×56). Layout: card glyph · state text (Newsreader italic 17) · trailing element.

| State | Text | Trailing element | Motion (off under Reduce Motion) |
|---|---|---|---|
| Idle | "Haku" | `⌥ SPACE` small caps, muted | none (optional idle animation is off by default) |
| Listening | "listening" with highlighter | ink squiggle waveform driven by the real mic level | the line redraws (stroke trim) |
| Thinking | "thinking" | three ink dots | dots fade in sequence, 1.2 s loop |
| Speaking | "speaking" + hand-drawn underline | `stop` link | the underline draws in, 2.2 s loop |
| Agent running | agent name ("Claude Code") | tally strokes (done = ink, todo = rule) + `2/5` | none; a stamp badge (blue ink ring, rotated −10°) shows how many jobs are running |
| Error | short reason ("mic unavailable") | `fix` link | none; red wavy underline + outlined glyph in `error` |

Behavior:

- Always on top, draggable, remembers its position, snaps to screen edges.
- **Idle opacity:** user setting, default 60%. Snaps to 100% on hover, while talking, or when anything needs attention.
- **Shapes:** Slip (default), Index tab (docks to a screen edge), Seal (52 px round stamp with an italic "h").
- **Reduced motion:** every state still reads with motion off. Keep the static frame (full squiggle, three dots, full underline).

## Expanded panel (460×640, opens from the widget)

- **Header (52):** glyph, "Haku", date · model in small caps, buttons for Tasks, Settings and Collapse.
- **Body:** two columns.
  - Conversation (left), Newsreader 16. The user's lines are italic, muted and prefixed with "—". Haku's lines are upright ink.
  - Margin (right, 128 wide), behind a `marginLine` rule. Running agent jobs live here as blue-ink italic notes, lined up with the message that started them, with `log` / `cancel` links.
- **Attachments:** shown as a taped photo (paper2 frame, tilted −1.5°, translucent highlighter tape). They are context only.
- **Workflows row:** "Workflows:" then underlined serif links.
- **Input:** a ruled line with a bottom border only, placeholder "Write, or hold ⌥ Space to speak", an attach button, and a round ink mic button (hold to talk). Paste supports images.

## Other surfaces

- **Tasks:** a 236 px list (agent in small caps, title in serif, working dir in mono, status in italic: blue = running, muted = done, red wavy = failed). The detail pane shows:
  - title and a meta list (dir, started, the original spoken ask, permissions)
  - numbered steps: done ones struck through, the current one highlighted
  - the live log (mono, follow toggle)
  - a summary once the job finishes
  - actions: Cancel / Open in Terminal, or Open diff / Copy summary / Run again
- **Confirmation:** a tear-off slip (dashed top edge). It has:
  - a small-caps source line and a serif question
  - the command or script in mono
  - consequences: red wavy for destructive ones, plus a link to "list them"
  - a "don't ask again for this workflow" checkbox
  - the voice line "say 'yes' or 'no'" with a live squiggle
  - Deny `esc` and Run `⏎`

  The agent variant adds a choice of agent, the folder, and an edits segment (Read only / Ask first / Allowed).
- **Workflows editor:**
  - name
  - trigger phrases (chips, plus "match similar wording")
  - action type (Ask model / Shell / Script / Agent), agent, folder
  - task template with variables `{after}` `{clipboard}` `{selection}` `{front app}` `{date}`, where `{after}` = whatever you say after the trigger phrase
  - safety toggles, an optional hotkey, "Try it by voice", Save
- **Settings sections:** General · Models & agents · Hotkeys & voice · Appearance · About.
  - Models: server type (LM Studio / Ollama / OpenAI-style), endpoint + status, model, fallback.
  - Agents: Claude Code and Codex (binary path, enabled, default edit permission), default folder, max concurrent jobs.
  - Hotkeys: Hold to talk `⌥Space`, Open panel `⌥⇧Space`, Tasks `⌥⇧T`, Stop/deny `esc`, Approve `⏎` (only while a prompt is open). These are placeholders, so check them for clashes.
  - Voice: STT engine (macOS on-device / local Whisper), languages (English, Slovenščina), when to speak replies, voice, rate, confirm by voice.
  - Appearance: theme grid, Light/Dark/Match system, highlighter color, widget shape, size, idle opacity, idle animation, density (Compact / Comfortable).
- **Onboarding:** 5 cards, with progress shown as tally strokes.
  1. Welcome
  2. Microphone (only while the hotkey is held or a prompt is waiting; nothing listens in the background)
  3. Speech recognition
  4. Accessibility (global hotkey + reading the front window)
  5. Try it

  Each permission card has three states: not asked, waiting for System Settings, allowed.

## SwiftUI notes

- **Widget window:** an `NSPanel` with `.nonactivatingPanel`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`. Host the SwiftUI view in it with `NSHostingView`.
- **Global hotkey:** SwiftUI `.keyboardShortcut` only works while the app is focused. Use Carbon `RegisterEventHotKey` or a small package such as KeyboardShortcuts. Hold-to-talk needs key-down and key-up.
- **Highlighter:** a custom `ViewModifier` that draws a `Rectangle` behind the lower part of the text with `.background(alignment: .bottom)`, inset by the line metrics. It needs light/dark variants, see the rule above.
- **Squiggle / underline animation:** a `Path` with `.trim(from:to:)` animated. Wrap every animation in a check of `@Environment(\.accessibilityReduceMotion)`.
- **Themes:** one `Theme` struct (colors + fonts + texture style + marking style + widget chrome), injected through the environment. Extra themes change the texture and marking style, not only the colors.
- **Fonts:** register the bundled fonts with `ATSApplicationFontsPath` in Info.plist or with `CTFontManagerRegisterFontsForURL`.
- **Contrast:** all text tokens pass 4.5:1 on their paper. Keep them that way when adding themes and test with Increase Contrast on.

## Suggested build order

1. Theme layer: tokens, fonts, highlighter modifier, paper surfaces.
2. Floating widget with all 6 states (feed it fake state first).
3. Expanded panel.
4. Confirmation prompt.
5. Tasks window.
6. Workflows editor.
7. Settings.
8. Onboarding.
9. Extra themes and widget options.

Ship each step as its own reviewable change.

## Open questions

- No wake word. Onboarding currently promises nothing listens in the background, so that's a product decision before adding one.
- Hotkeys are placeholders.
- Mockup copy (devenv tests, Caddy cert, Keycloak) is sample content. Replace it with real data from the app.
