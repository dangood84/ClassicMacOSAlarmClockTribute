# Alarm Clock

A tribute to the Macintosh **Alarm Clock** desk accessory: a small black-and-white panel with no system window frame around it. The time and the date are bold Geneva, centered, with a little key to the right of the time. That key is the lever. It points up when the panel is compact. Click it and the key turns down, a line opens under the time, and three pictures appear — a clock, a calendar, and an alarm. The line shows whichever picture is selected.

Written in **Free Pascal**. Lazarus and Delphi are not required. `fpc` plus the platform GUI libraries already on the machine are enough. The face is a software RGBA canvas; each host only uploads those bytes into a native window.

## Was it System 7? Was it in Mac OS 8 or 9?

It is older than System 7. The Alarm Clock shipped with the original Macintosh in **January 1984** (System 1). Donn Denman wrote part of it, alongside the Notepad and part of the Calculator. It lived in the Apple menu through System 6 and through **System 7.0 and 7.1** (a version 7 of the desk accessory, in the Apple Menu Folder).

**System 7.5 removed it.** Setting the clock, and the menu-bar clock, moved to the Date & Time control panel. **Mac OS 8 and Mac OS 9 did not include the Alarm Clock.** Both still knew how to *run* an old desk accessory if you had kept the file, but a normal install used Date & Time instead. Mac OS 9.0.4 is also where Apple fixed the classic 2020 date limit in that control panel; System 7's Alarm Clock itself refused years outside 1921–2020.

## What this one does

- Shows **local time**, 12-hour, with seconds, and jumps once a second
- Opens and closes on the **lever**. The window grows downward; the top edge stays put
- Open, one line under the time and three pictures: a clock, a calendar, and an alarm. The line shows whichever picture is lit. Opening the key lights the calendar. The knob sits to the left of the alarm time. The pointer turns into a crosshair on that line
- Knob up arms the alarm. It becomes live when you leave that row, close the lever, or close the window — the same rule as the 1990 Macintosh LC manual. It does not ring while you are still editing it
- One beep when the time is reached, then the time plaque **inverts** until you turn the knob down. The original alternated an alarm glyph with the Apple mark in the menu bar; this window does that job itself and does not draw Apple's logo
- Date and time can be edited with the arrows or the keyboard. That moves **this clock only**. The Mac, Windows, and Raspberry Pi system clocks stay where they are. **Alarm Clock → Use System Time** clears the offset
- The alarm time and the knob are saved, and come back the next launch

How the pieces fit together (same style as the RISC OS clock, Eyes, and the calculator): `WORKINGS.md` for responsibilities and the alarm states, `EXECUTION_FLOW.md` for a tick-by-tick trace.

## Requirements

- **Free Pascal** 3.2+ (`fpc` on your `PATH`)

macOS Sonoma (this M1 Mac), Homebrew:

```bash
brew install fpc
```

macOS Catalina (the 2014 Intel Mac): current Homebrew no longer supports 10.15. The official Free Pascal **3.2.2 Intel** installer from [freepascal.org](https://www.freepascal.org/) still does. The app's minimum system version is 10.13, and it stays on AppKit calls from that era. Build it on the Catalina machine; this tree does not cross-compile.

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
```

Windows 10 (including Boot Camp): a native Free Pascal install. The `Windows` unit ships with FPC.

## Run

From the project root, on the machine you want to run on:

```bash
make
make run
```

That compiles to `build/` and opens `AlarmClock.app` on macOS. The window is a real app with a Dock icon, parked at the upper right under the menu bar.

Or with Make on the other OSes:

```bash
make linux      # Linux / Raspberry Pi OS window
make windows    # AlarmClock.exe
make test       # headless alarm-state checks (no GUI)
make snap       # PPM frames of the canvas
make clean      # remove build/
```

Manual compile on macOS (Make still wraps the binary in the `.app`):

```bash
fpc -Mobjfpc -Scgi -O2 -Fusrc -FUbuild -FEbuild -obuild/AlarmClock src/alarm.pas
make app
open build/AlarmClock.app
```

## Using it

1. The big time follows the system clock until you edit it.
2. Click the **key**. The date appears, the middle calendar lights, and under the line three pictures: a clock, a calendar, and an alarm.
3. Click the **alarm** picture (the right-hand box). The line shows the alarm time. Click the **knob** so it sits at the top of its track.
4. Click a part of the time (hour, minute, second, AM/PM). The up and down arrows appear. Click them, or use the arrow keys. Digits work too. `A` and `P` set AM and PM.
5. Close the lever, click another button, or click the close mark. That arms the alarm. While the alarm line is still selected, it will not ring.
6. At that time the machine beeps once and the time inverts, about twice a second, until the knob goes down.
7. **Esc** or **Return** closes the panel. **Tab** walks date → clock → alarm.

The close mark **quits**. Drag an empty part of the face to move the panel. On Windows and the Pi, right-click for About, Use System Time, and Quit. The original desk accessory could keep ringing after its window closed, because it lived in the system. This program rings while it is open.

## Where it appears

| OS | Presence |
|----|----------|
| **macOS** | Borderless window, Dock icon, upper right. Retina buffer is an integer scale so Geneva stays sharp. Catalina at 1× stays 1×. |
| **Windows** | Borderless window on the taskbar, upper right of the work area. |
| **Linux** | Borderless GTK 2 window (Raspberry Pi OS friendly). |

The user does not drag the border. The lever is what changes the height, which is what the desk accessory did.

## Project layout

```
src/
  alarm.pas          # program; picks the host with {$IFDEF}
  ualarmmodel.pas    # clock offset, alarm states, editing, prefs
  ualarmrender.pas   # software RGBA canvas, pictures, hit testing
  ualarmtext.pas     # Geneva on a Mac; 5×7 widths elsewhere
  ualarmapp.pas      # TAlarmController: tick, click, key, present flag
  uhostcocoa.pas     # macOS NSWindow
  uhostwin.pas       # Windows HWND
  uhostgtk.pas       # Linux GtkWindow
  alarmtest.pas      # headless state checks
  alarmsnap.pas      # paints PPM frames without a window
bundle/
  Info.plist         # 10.13+, retina-capable app bundle
Makefile
```
