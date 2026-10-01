# Execution flow: from `begin` to a drawn second

A step-by-step trace of what happens from `program AlarmClock` through host initialisation and timer startup, down to how a second is drawn and how an alarm becomes armed.

Default launch (`make run`) opens the **macOS window**. `make windows` / `make linux` use the same model and renderer; only the present step changes. This trace is **macOS** (`uhostcocoa`) unless a step says otherwise.

One thread does everything after startup:

- **main (Pascal, then Cocoa run loop)** — `HostRun`, `setup`, `tick:`, `redraw`, AppKit drawing

There is no separate timer thread. `NSTimer` and `NSWindow` run on the same thread that called `NSApplication.run`.

---

## Phase A — process entry

**1.** The OS loads `AlarmClock.app/Contents/MacOS/AlarmClock` (or `./build/AlarmClock`). FPC unit initialisation runs (`TAlarmModel` is not constructed yet).

**2.** `program AlarmClock` executes `HostRun`.

```pascal
{ src/alarm.pas }
begin
  HostRun;
end.
```

**3.** `HostRun` (Cocoa):

```pascal
procedure HostRun;
var
  Pool: NSAutoreleasePool;
  App: NSApplication;
begin
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyRegular);
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup;
  App.run;
  Pool.release;
end;
```

Regular policy (no `LSUIElement`) means: **Dock icon**, Cmd-Tab, a real window. `App.run` does not return until Quit.

Windows: `HostRun` registers a window class, `CreateWindowEx` with `WS_POPUP` (no caption; the drawn close mark quits), `SetTimer`, then `GetMessage`.
Linux: `gtk_init`, `gtk_window_new`, `g_timeout_add(100, ...)`, `gtk_main`.

---

## Phase B — window initialisation (`setup`)

**4.** `TAppDelegate.setup` is idempotent (`if ready then Exit`). `applicationDidFinishLaunching` calls it again after `App.run` has started; the second call is a no-op.

**5.** Pixel scale: `NSScreen.mainScreen.backingScaleFactor`, rounded to an integer. Typically `2` on Sonoma retina, `1` on a non-retina Catalina display. The controller buffer is in **pixels**; the window is in **points** (128×20 at launch, compact).

**6.** `controller := TAlarmController.Create(scale, AlarmSettingsFile)`:

- `TAlarmModel.Create` loads `alarm.ini` if it exists. Knob up in that file means the alarm is already armed — a fresh process is never mid-edit
- The first `Sample` records the current second and **does not ring**, even if that second is the alarm
- `TPixelBuffer` allocated (RGBA), compact size
- `NeedsPresent := True` so the first paint happens before the timer

**7.** Menu: About, Use System Time, and Quit on the application menu.

**8.** Window: borderless (`NSBorderlessWindowMask`), with a shadow, **not** resizable. Content rect is the upper right of `visibleFrame`, just under the menu bar — where the LC manual put the desk accessory. Content view is `TAlarmView` (unflipped). The canvas is top-left, so mouse y is `height - cocoaY`. `canBecomeKeyWindow` and `canBecomeMainWindow` are both true so a borderless window still takes keys and the Alarm Clock menu.

**9.** `redraw` → `controller.Render` → `RenderAlarm` → copy into a fresh `NSImage` → `setNeedsDisplay`. The window is not blank when it appears.

**10.** Timer is armed at **0.1 s** (10 Hz). That is only so we notice the second change quickly, and so a ringing plaque can invert about twice a second (`PulseBlink` flips every five ticks). The face is painted when something visible changed, not on every tick.

```pascal
animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
  0.1, self, objcselector('tick:'), nil, True);
```

**11.** `App.run` starts.

---

## Phase C — per-tick update (main thread, ~10 times per second)

**12.** The timer fires → `tick:`. A fresh `NSAutoreleasePool` wraps the tick.

**13.** `controller.Tick` → `TAlarmModel.SyncFromSystem`:

```pascal
procedure TAlarmModel.Sample;
begin
  if FFrozen then
    Exit;          { snapshots / tests: Now() must not move the clock }
  DT := Now + FOffsetSec / SecsPerDay;
  DecodeDate(DT, ...);
  DecodeTime(DT, ...);
  ApplyDisplay(W);
end;
```

**14.** `ApplyDisplay` is the second-and-alarm state change:

```pascal
if FHavePrev and FCommitted and (not FRinging) then
  if AlarmCrossed(FPrevSOD, SOD, Target) then
  begin
    FRinging := True;
    FBeep := True;
    FBlinkOn := True;
  end;
```

Most ticks: the wall time is unchanged, `Dirty` stays false, `tick:` returns without drawing.
On a new integer second: `NeedsPresent := True` and we fall through to Phase D.
On a crossing while armed: the same, plus `ConsumeBeep` makes the host call `NSBeep` once.

Windows: `WM_TIMER` is not the clock. Time is still `Now`.
Linux: `g_timeout_add` → `OnTick` → the same `Tick`.

---

## Phase D — draw (`redraw` then AppKit)

**15.** `controller.Render` asks `Model.Snapshot` for the wall time, the knob, the selected part, and the blink phase.

**16.** `RenderAlarm`:

1. Clear white
2. Bold Geneva time, centered between the close square and the key. Ringing and the blink phase draw that string white on a black plaque. The quiet phase draws it black
3. The key: tooth up when compact, turned 180 degrees (tooth down) when open
4. The close square
5. If expanded: a rule, then one centered line for the lit picture (date, a copy of the time, or the knob plus the alarm time), then three pictures — clock, calendar, alarm. The lit picture is filled black and drawn in white. Arrows appear on the line only after a digit is clicked

**17.** `MakeImage` allocates an `NSBitmapImageRep` with **nil planes** (AppKit owns the bytes), copies `Canvas.Ptr` into `bitmapData`, and wraps that in a new `NSImage`. The previous `frameImage` is released. Do **not** alias the Pascal buffer: AppKit would cache the first frame.

**18.** `TAlarmView.drawRect` fills white and `frameImage.drawInRect`.

---

## The lever (a different window size, same draw loop)

**19.** A click with `clickCount = 1` converts to logical pixels and `PointerDown`.

**20.** A hit on the lever calls `ToggleLever`:

```pascal
{ State change: compact → expanded. The lever points down and the
  date is the line on show, so the middle picture is the one lit. }
FExpanded := True;
if FRow = rowNone then
  SelectRow(rowDate);
```

Closing the lever while the alarm row is selected calls `FinishAlarmEdit` first. Knob up → **armed**. Knob down → ringing stops.

**21.** The host sees `WantsResize`, calls `ApplyChrome` (buffer rebuilt to the new height), then `setFrame:display:` with the **top edge pinned**. The desk accessory grew downward. `setContentSize` alone would grow upward, into the menu bar.

**22.** `redraw` paints the new buffer into the new bounds.

Windows: `MoveWindow` keeps the current top-left and the new client height.
Linux: `gtk_window_resize` after a brief resizable toggle, so the window manager applies it.

---

## Arming an alarm

**23.** Click the lower-right picture, or the alarm time. `SelectRow(rowAlarm)` suspends `FCommitted`.

**24.** Click the knob. `ToggleSwitch` moves it up. Because the alarm row is still selected, the alarm is **not** live yet.

**25.** Click a part (hour, minute, second, AM/PM). Arrows appear on that row. `Nudge(+1)` or a digit changes only that field. 12 AM is midnight (`Hour24Of(12, False) = 0`). 12 PM is noon.

**26.** Close the lever, click the date or the clock, or close the window. `FinishAlarmEdit` sets `FCommitted`. The prefs file is rewritten.

**27.** Later, `ApplyDisplay` sees the displayed seconds-of-day move forward across the alarm and enters **ringing**. One beep. `PulseBlink` inverts the plaque every half second until the knob goes down.

Editing the date or the clock calls `SetDisplayedWall`, which stores `FOffsetSec = wanted - Now`. The next samples keep counting from the time you set. The OS clock is untouched. A small **SET** mark is drawn at the left of the time while the offset is on. **Use System Time** clears it.

---

## The repeating loop

```text
NSTimer (~100 ms, main thread)
  → tick:  Model.SyncFromSystem
  → PulseBlink if ringing
  → if the second, the blink, or an edit changed the picture:
        Snapshot
        RenderAlarm
        MakeImage copy → drawRect
  → if the lever moved:
        resize the window from the top edge, then the same draw
  → wait for the next timer event
```

Quit: menu **Quit** or the close box → `CommitForClose` → `NSApplication.terminate`. `applicationShouldTerminateAfterLastWindowClosed` ends the process.

---

## Windows path (same draw loop)

`WM_TIMER` → `Tick` → if `NeedsPresent` then `Present`:

1. `RenderAlarm`
2. `CopyBGRA` (Windows DIB is BGRA)
3. `InvalidateRect` → `WM_PAINT` `StretchDIBits`

`WM_LBUTTONDOWN` is a logical-pixel click (scale 1). `WM_SETCURSOR` shows the crosshair on the line under the time. `WM_CHAR` supplies digits and `A` / `P`.

---

## Linux path (same draw loop)

`OnTick` (glib timeout):

1. `Controller.Tick`
2. If dirty: `RenderAlarm`, copy RGBA into a `GdkPixbuf` (rowstride may be wider than `width*4`)
3. `gtk_widget_queue_draw` → `expose-event` `gdk_pixbuf_render_to_drawable`

`button-press-event` ignores `GDK_2BUTTON_PRESS` so a double-click does not toggle the lever twice. `gdk_beep` is the ring.

---

## One-line map

`begin HostRun` → `setup` (window + 10 Hz timer) → **`SyncFromSystem` until the second changes** → **`RenderAlarm` writes RGBA** → **host copies a snapshot onto the window**. A click on the lever is the other path: **`ToggleLever` → window height → the same draw**.

Debugger: `HostRun`, `TAppDelegate.setup`, `TAlarmModel.ApplyDisplay`, `TAlarmModel.FinishAlarmEdit`, `RenderAlarm`, `MakeImage`. The first paint happens in `setup`, before the timer. `FHavePrev` is what stops that first sample from ringing.

See also `WORKINGS.md` for the four alarm states, the crossing rule, and why the year nudge stops at 1921 and 2099.
