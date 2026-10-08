# Raicode Pet — Design

**Date:** 2026-10-08
**Status:** Draft for review

## Goal

A Codex-Pets-style desktop companion for Raicode (Claude Code CLI): a cute pixel-art dog that floats on top of everything and shows, at a glance, what Raicode is doing — above all, **when a task is finished or needs input**. Built from scratch, no third-party code.

**Audience:** Matthias, on his own Mac. Not distributed.

**Success looks like:** while working in another app, he glances at the dog and knows whether Raicode is working, waiting on him, done, or broken — and one click takes him back to the right terminal.

## Constraints

- macOS only (built and tested on macOS 27; target macOS 14+).
- Native Swift + SwiftUI/AppKit, Swift Package Manager. Zero third-party dependencies.
- Driven exclusively by Claude Code hooks. Never blocks, slows, or makes decisions for Raicode.
- Never modifies anything in `~/.claude/settings.json` except its own tagged hook entries.

## Architecture

```
Raicode hook fires ─▶ RaicodePet hook <event>  ─▶  ~/.raicode-pet/sessions/<session_id>.json
                       (same app binary, stdin JSON)          │
                                                              ▼ file watcher (FSEvents + 10 s poll fallback)
                                                     SessionStore → aggregate state
                                                              ▼
                                               DogWindow (NSPanel) + MenuBar item
```

### Units

| Unit | Responsibility | Depends on |
|---|---|---|
| **HookCommand** | Entry point when the binary runs as `RaicodePet hook`. Reads hook JSON from stdin, maps it to a session state, writes `<session_id>.json` atomically, exits 0. Always exits 0, even on bad input. Target runtime < 50 ms. | EventMapper, SessionFile |
| **EventMapper** | Pure function: (hook event name, matcher fields, previous state) → new session state or delete. | — |
| **SessionFile** | Codable model + atomic read/write of one session record. | — |
| **SessionStore** | Watches the sessions folder, loads records, prunes stale ones, publishes the aggregate state and the session list. | SessionFile, Aggregator, Pruner |
| **Aggregator** | Pure function: [sessions] → single dog state by priority. | — |
| **Pruner** | Pure function deciding which records are stale. | — |
| **DogSprites** | Pixel-art frames as character grids + colour palette. Data only. | — |
| **DogView** | Renders the current state's frames (nearest-neighbour scaling) with animation timing, speech bubble. | DogSprites |
| **DogWindow** | Borderless, transparent, non-activating `NSPanel`; floats over all spaces and full-screen apps; draggable; position persisted and clamped to visible screens. | DogView |
| **TerminalFocuser** | Brings the terminal app owning a session to the front. | — |
| **HookInstaller** | Adds / removes the app's tagged hook entries in `~/.claude/settings.json` with a backup. | — |
| **MenuBar** | Status item: show/hide dog, session list, install/remove hooks, launch at login, quit. | SessionStore, HookInstaller |

### Session record

```json
{
  "sessionId": "abc123",
  "cwd": "/Users/matthias/Projects/eufemia",
  "project": "eufemia",
  "state": "working",
  "detail": "Bash",
  "terminalPid": 4242,
  "updatedAt": "2026-10-08T10:15:00Z"
}
```

`terminalPid` is the hook process's parent chain resolved to the Claude Code process PID (used for focusing and liveness).

## States and event mapping

| Hook event | Session state |
|---|---|
| `SessionStart` | idle |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStart` | working |
| `PermissionRequest`; `Notification` with `permission_prompt`, `elicitation_dialog`, `agent_needs_input` | waiting |
| `Stop` | done |
| `StopFailure` | failed |
| `SessionEnd` | record deleted |
| anything else | ignored (no change) |

`PostToolUseFailure` is deliberately **not** mapped to failed — tool failures are routine and Claude recovers from them. Only a turn ending in an API error counts as failed.

**done** persists until the dog is clicked or a new prompt starts in that session. **failed** behaves the same way.

**Aggregate priority** (one dog for all sessions): waiting > failed > done > working > idle. No sessions → idle.

## The dog

- Pixel-art dog in the Codex Pets style: ~32×32 logical pixels scaled ×5 (≈160 pt), crisp nearest-neighbour edges, dark outline.
- Default palette: warm tan coat, cream belly/muzzle, dark outline, pink tongue, red collar. One palette definition, easy to change.
- Frames stored in `DogSprites.swift` as string grids (one character per pixel) with a legend at the top.

| State | Animation (2–4 frames) | Bubble |
|---|---|---|
| idle | curled up asleep, floating "z"; occasional stretch | hidden |
| working | trots in place, ears bounce | `<project>: working…` (+ tool name) |
| waiting | sits up, paw raised, small hops | `<project>: needs you!` |
| done | sits, tail wags, tongue out | `<project>: Done!` |
| failed | ears down, sad eyes, "…" | `<project>: something broke` |

- On entering **waiting** or **done**, a native macOS notification fires (once per transition) and a short system sound plays; both toggleable in the menu.
- Reduce Motion on → a single still frame per state.

### Codex pet support (added after review)

If a Codex-format pet is installed, it replaces the built-in pixel dog. Default: **Jin Mao** (personal use only, never redistributed).

- Location: `~/.raicode-pet/pets/<name>/` with `pet.json` (`id`, `displayName`, `spritesheetPath`) + spritesheet (PNG/WebP). Also picks up `~/.codex/pets/`.
- Atlas: 8 columns × N rows of 192×208 cells. Row order: `idle, running-right, running-left, waving, jumping, failed, waiting, running, review`, optional `stretching, looking-around`. Frame count per row = cells until the first fully transparent one.
- State → row: idle→`idle` (with occasional `stretching`/`looking-around`), working→`running`, waiting→`waiting`, done→`review` (plays `jumping` once on entering), failed→`failed`. Clicking/waking plays `waving` once.
- Rendered at native 192×208 cell size scaled to ~0.75× (≈144×156 pt), smooth scaling.
- Menu: *Pet* submenu lists installed pets + built-in pixel dog; choice persisted.

## Interaction

- **Click dog:** one session → focus its terminal and clear done/failed. Several sessions → small popover list sorted by priority; clicking a row focuses that terminal.
- **Drag dog:** moves it; position remembered.
- **Menu bar:** Show/Hide Dog, sessions list, Notifications on/off, Sounds on/off, Install Hooks, Remove Hooks, Launch at Login, Quit.

**Terminal focusing:** walk the process tree from the Claude Code PID up to the first GUI app (Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor, …) and activate it. Tab-level focusing is out of scope; raising the app window is enough.

## Hook installation

- Menu → *Install Hooks* adds one command hook per mapped event, all pointing at `<app bundle>/Contents/MacOS/RaicodePet hook`.
- Every added entry is identifiable (command path contains `RaicodePet hook`) so *Remove Hooks* deletes exactly those and nothing else.
- Before writing: copy settings to `~/.claude/settings.json.raicode-pet.bak`. Existing hooks for the same event are kept (new matcher group appended). Writes are atomic. Unparseable settings file → abort with an alert, never overwrite.
- Status line, permissions, and all other keys untouched.

## Error handling

- App not running → hook still writes the file and exits immediately.
- Malformed stdin / unknown event / missing `session_id` → no-op, exit 0.
- Stale records: deleted if the recorded PID no longer exists, or not updated in 6 hours.
- Dog off-screen (monitor unplugged, resolution change) → clamped back onto the nearest visible screen.

## Testing

- **Unit tests (swift test):** EventMapper, Aggregator, Pruner, SessionFile round-trip, HookInstaller install/remove on fixture settings files (existing hooks preserved, idempotent install, clean removal, malformed file refused).
- **Visual check:** a debug command renders every pose/frame to PNGs for review before wiring into the window.
- **Manual end-to-end:** install hooks, run a Raicode session, observe working → waiting → done transitions and click-to-focus.

## Project layout

```
~/Projects/raicode-pet/
  Package.swift
  Sources/RaicodePetCore/   # pure logic: EventMapper, Aggregator, Pruner, SessionFile, HookInstaller
  Sources/RaicodePet/       # app: main (hook vs UI mode), SessionStore, DogSprites, DogView, DogWindow, MenuBar, TerminalFocuser
  Tests/RaicodePetCoreTests/
  build_app.sh              # builds RaicodePet.app (ad-hoc signed)
```

## Out of scope (for now)

Cost/usage tracking, streaks/XP, a pet gallery / per-project pets, one dog per session, tab-level terminal focus, Windows/Linux, distribution/notarization.
