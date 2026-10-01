# How Alarm Clock works

This note is for someone who wants to **build and run** the tribute on each OS, and to see how a small Free Pascal desk accessory is structured: where it starts, who owns the alarm, who paints pixels, and how the lever changes the window.

You do not need to be a Cocoa, Win32, or GTK expert. The same ideas show up in the RISC OS clock and Goody's Calculator: an entry point, a model, a software canvas, and a native host that only presents bytes.

There is **no Lazarus form**. The face is black ink on white. On a Mac the time and the date are bold Geneva, centered. Compact is that time, a close square, and a key. Open, the key turns, the date line appears with the calendar lit, and under it three pictures: a clock, a calendar, and an alarm. Those pixels go into a borderless window.

## Build / run workflows

Work from the project root. `fpc` must be on `PATH`. Output always lands in `build/` (gitignored).

| What you want | Command | What you get |
|---------------|---------|--------------|
| macOS app | `make` then `make run` | `build/AlarmClock.app`, opened |
| Linux / Raspberry Pi OS | `sudo apt install fpc libgtk2.0-dev` then `make linux` then `./build/alarmclock` | GTK 2 window |
| Windows 10+ | from a native FPC prompt: `make windows` then `build\AlarmClock.exe` | taskbar window |
| Headless state checks | `make test` | prints `ok` lines; non-zero if a state is wrong |
| Frozen canvas frames | `make snap` | seven PPMs in `build/`, from `snap-compact.ppm` to `snap-ring-quiet.ppm` |
| Start over | `make clean` | deletes `build/` |

macOS Sonoma (Apple silicon, Homebrew):

```bash
brew install fpc
make
make run
```

macOS Catalina (2014 Intel): install the official FPC 3.2.2 Intel package, then the same `make` / `make run`. Homebrew's current formula does not support 10.15.

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
make linux
./build/alarmclock
```

Windows: install FPC, open its command prompt so `fpc` is on `PATH`, then `make windows`. The `Windows` unit ships with FPC; no extra SDK is required.

Only **one** host unit is compiled. `{$IFDEF DARWIN}` / `WINDOWS` / else picks `uhostcocoa`, `uhostwin`, or `uhostgtk`. Cross-compiling the GUI hosts is not a supported workflow — build on the OS you want to run on. An M1 Sonoma binary will not run on the Catalina Mac, and the other way around.

## Lever workflow (all three hosts)

| Action | What happens |
|--------|----------------|
| Click the lever | Compact ↔ expanded. Opening lights the calendar, because the date is the line on show. Closing commits a pending alarm. The top-left of the window stays put, so the window grows and shrinks downward. |
| Esc or Return | Closes the panel, which also commits a pending alarm. |
| Close box | Commits a pending alarm, then the process ends. |

The pixel buffer is `128 × height` logical pixels (20 compact, 72 open), times an integer device scale (2 on a retina Mac, 1 on Catalina, Windows, and the Pi). A fractional scale would blur Geneva and the fallback pixel face, so the Mac host rounds `backingScaleFactor`.

## Mental model

```
alarm.pas begin
  → HostRun                    # uhostcocoa / uhostwin / uhostgtk
      → create TAlarmController (model + pixel buffer)
      → create a small borderless window, upper right
      → timer (~10 Hz)
           → Model.SyncFromSystem
           → if the second changed, the blink flipped, or the user edited:
                 RenderAlarm (RGBA pixels)
                 host shows the buffer
           → if the lever moved:
                 host changes the window height
```

| Layer | Unit | Tester-friendly analogy |
|-------|------|-------------------------|
| Entry / routing | `alarm.pas` | Test runner that picks the OS host at compile time |
| State | `ualarmmodel` | Fixture: wall time, offset, alarm knob, armed / ringing |
| Composer | `ualarmapp` | Holds the model and the canvas; `NeedsPresent` is the dirty flag |
| View | `ualarmrender` | The thing that paints the time, the lever, the date, and the three boxes |
| Window shell | `uhostcocoa` / `uhostwin` / `uhostgtk` | Window, timer, beep, About / Use System Time / Quit |

The hosts are **event-driven**. Almost everything after `HostRun` runs on the GUI thread. That is why the clock uses `NSTimer` / `SetTimer` / `g_timeout_add` instead of a raw `while true` loop.

## Alarm states

```
off        knob down. Nothing is waiting.
editing    knob up, and the alarm row is selected. Not live yet.
armed      knob up, and the user has left that row (lever, another row, or the close box).
ringing    the displayed clock moved forward across the alarm time.
           One beep. The time plaque inverts until the knob goes down.
```

The 1990 Macintosh LC manual is the source of the editing rule: the alarm will not go off unless you close the lever, select another area, or click the close box. `FinishAlarmEdit` is that rule. Selecting the alarm row suspends a live alarm so it cannot fire while its digits are being changed.

Firing uses a **crossing**, not "the seconds happen to be equal on this 10 Hz sample". A hiccup that skips a second still rings. A backward nudge (minute down) is not treated as midnight, or setting the clock back would ring almost everything. The first sample after launch establishes where the clock was and does not ring just because the program opened on the alarm second.

## Unit responsibilities

### `alarm.pas` — composition root

- Picks the host with `{$IFDEF}`
- Calls `HostRun`
- Does not decode time or draw the lever

### `ualarmmodel` — time, offset, alarm

- `SyncFromSystem` reads local `Now` plus `FOffsetSec`, unless `FreezeAt` was called
- Editing the date or the time changes the offset. The original desk accessory called `SetDateTime` and wrote the Mac's clock chip. This tribute never does that
- **Alarm Clock → Use System Time** (`ResetToSystem`) clears the offset and forgets the previous sample, so the jump back is not itself a crossing
- Year nudges clamp to **1921..2099**. System 7's Alarm Clock stopped at 2020; a machine today is already past that, so the tribute goes through 2099 and still will not walk back before 1921
- Hour, minute, second, and AM/PM are separate fields. 11 AM nudged by one hour becomes 12 AM, not 12 PM. AM/PM is its own click
- Prefs are `alarm.ini` inside Free Pascal's per-user config directory (`GetAppConfigDir`). On this Mac that is `~/.config/AlarmClock/alarm.ini`. Tests pass an empty path and do not touch disk

### `ualarmrender` — software canvas

- `TPixelBuffer`: packed RGBA (`Width × Height × 4`)
- Logical size is 128 points wide. Compact height is 20: close square, time, and the key with its tooth up. Expanded adds 52: the line under the time, then three picture buttons. Opening the key turns it 180 degrees so the tooth points down
- Compact is the time and the key. Open, one line shows whichever picture is lit, and under it three pictures — clock, calendar, alarm. Opening the key lights the calendar. Clicking the clock puts a copy of the time on the line. The knob sits to the left of the alarm time. The date is `month/day/year`, two digits of the year, the way `9/27/84` was. The calendar picture itself is a 2 on the back sheet and a bold 1 on the front; it is not the live day
- On a Mac the time and the date are bold Geneva, centered on their line, drawn by AppKit from the font already installed. Geneva has no bold face, so the tribute draws it twice, one pixel apart. The outlines are not copied into this project. Hosts without Geneva fall back to the 5×7 pixel face, smeared the same way
- A close mark is drawn on the face. Hosts have no system title bar, so that mark is what quits, and a click on empty pixels is a drag
- The 5×7 glyphs are original. They are not Chicago, and they are not a copy of the desk accessory's bitmaps
- `BuildLayout` and `HitTest` share one geometry, so a click lands on the pixels you see
- `CopyBGRA` swaps channels for a Windows DIB

### `ualarmapp` — one controller

- Owns `TAlarmModel` and `TPixelBuffer`
- `Tick` → `SyncFromSystem` and `PulseBlink`. `NeedsPresent` when anything visible changed
- `WantsResize` when the lever moved. The host changes the native window, then `ApplyChrome` rebuilds the buffer
- `PointerDown` / `Key` translate hits and keys into model calls
- `ConsumeBeep` is the one-shot the host plays (`NSBeep`, `MessageBeep`, `gdk_beep`)

### Hosts

- **Cocoa:** `NSBorderlessWindowMask`, a shadow, not resizable. The menu bar still has About, Use System Time, and Quit (`canBecomeMainWindow`). Timer 0.1 s. Backing store is `points × rounded backingScaleFactor`. `setFrame:display:` keeps the top edge when the lever moves, and also moves the window when empty pixels are dragged. Mouse y is flipped because `NSView` origin is the bottom-left and the canvas origin is the top-left. A double-click's second `mouseDown` (`clickCount > 1`) is ignored so the lever does not open and immediately close.
- **Win32:** `WS_POPUP` (no caption), `WM_TIMER` 100 ms, `StretchDIBits`. Empty pixels send `WM_NCLBUTTONDOWN` / `HTCAPTION` to drag. Right-click is a popup menu. `WM_SETCURSOR` shows `IDC_CROSS` on the line under the time.
- **GTK 2:** `gtk_window_set_decorated(False)`, `gtk_window_set_resizable(False)`, `g_timeout_add(100, ...)`, drawing area + `GdkPixbuf`. Empty pixels call `gtk_window_begin_move_drag`. Right-click pops the menu. The lever toggles resizable around `gtk_window_resize` so the window manager honours the new height. Keys are delivered on the toplevel window.

## Debugger map

Break on `HostRun`, `TAlarmModel.ApplyDisplay` (the ringing state change), `TAlarmModel.FinishAlarmEdit` (armed), `TAlarmModel.ToggleLever`, `RenderAlarm`, and the host present (`redraw` / `Present` / `OnExpose`). You will see: **timer → maybe a new second → maybe a crossing → paint → upload**.
