program AlarmClock;

{$mode objfpc}{$H+}
{$IFDEF DARWIN}
{$modeswitch objectivec1}
{$linkframework Cocoa}
{$ENDIF}

{ Classic Mac Alarm Clock — desk-accessory tribute in Pascal.

  macOS:    small titled window, upper right, grows when the lever opens.
            Dock icon. Integer backing scale so the pixel font stays crisp
            on an M1 Sonoma display and a 1× Catalina display.
  Windows:  same window on the taskbar (Boot Camp included).
  Linux:    GTK 2, which is what Raspberry Pi OS still ships as libgtk2.0.

  Only one HostRun is linked. Build on the machine you want to run on.
  See the Makefile. }

uses
  {$IFDEF DARWIN}
  uhostcocoa
  {$ELSE}
    {$IFDEF WINDOWS}
    uhostwin
    {$ELSE}
    uhostgtk
    {$ENDIF}
  {$ENDIF};

begin
  HostRun; { Cocoa run loop, Win32 GetMessage, or gtk_main — see uhost*.pas }
end.
