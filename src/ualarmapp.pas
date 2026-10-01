unit ualarmapp;

{$mode objfpc}{$H+}

{ One model, one canvas. Hosts call Tick on a timer, PointerDown and Key
  when the user clicks or types, and present Canvas when NeedsPresent is set.

  WantsResize is the lever. The host changes the native window's content
  height; ApplyChrome rebuilds the buffer to the compact or expanded size.
  The desk accessory grew and shrank the same way. It was not a fullscreen
  face. }

interface

uses
  ualarmmodel, ualarmrender;

const
  AlarmAboutTitle = 'Alarm Clock';
  AlarmAboutText =
    'A tribute to the Macintosh Alarm Clock desk accessory.' + LineEnding + LineEnding +
    'It shipped with the original Mac in 1984, stayed in the Apple menu through ' +
    'System 7.1, and was removed in System 7.5. Mac OS 8 and Mac OS 9 did not ' +
    'include it. The Date & Time control panel and the menu-bar clock replaced it.' +
    LineEnding + LineEnding +
    'Click the lever to open the panel. The date appears, then three boxes: ' +
    'a clock, the setting, and the alarm. The knob to the left of the alarm ' +
    'time arms it. The alarm becomes live when you leave that setting, close ' +
    'the lever, or close the panel.' + LineEnding + LineEnding +
    'Setting the date or the time moves only this clock. It does not change the ' +
    'Mac, Windows, or Raspberry Pi clock. Use System Time puts it back.' +
    LineEnding + LineEnding +
    'When it rings, the time inverts (the original flashed an alarm icon in ' +
    'place of the Apple menu) and the machine beeps once. Turn the knob down ' +
    'to stop the blinking.';

type
  TAlarmKeyKind = (
    akUp, akDown, akLeft, akRight, akTab, akEscape, akReturn,
    akDigit, akLetter
  );

  TAlarmController = class
  private
    FScale: Integer;
    FNeedsPresent: Boolean;
    FWantsResize: Boolean;
    FWantsQuit: Boolean;
    procedure NoteChanges;
  public
    Model: TAlarmModel;
    Canvas: TPixelBuffer;
    constructor Create(PixelScale: Integer; const SettingsFile: string);
    destructor Destroy; override;
    procedure Tick;
    { True when the click missed every control, so the host should drag
      the borderless panel. WantsQuit is the drawn close mark. }
    function PointerDown(X, Y: Integer): Boolean;
    procedure Key(Kind: TAlarmKeyKind; Extra: Integer);
    procedure Render;
    procedure ApplyChrome;
    procedure CommitForClose;
    function ConsumeBeep: Boolean;
    function WantsCrosshair(X, Y: Integer): Boolean;
    function ContentWidth: Integer;
    function ContentHeight: Integer;
    property NeedsPresent: Boolean read FNeedsPresent;
    property WantsResize: Boolean read FWantsResize;
    property WantsQuit: Boolean read FWantsQuit;
    property Scale: Integer read FScale;
    procedure ConsumePresent;
  end;

function AlarmSettingsFile: string;

implementation

uses
  SysUtils;

function AlarmSettingsFile: string;
begin
  { FPC picks the per-user config directory for this OS. The file is
    alarm.ini inside it. Empty string in tests means "do not touch disk". }
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'alarm.ini';
end;

constructor TAlarmController.Create(PixelScale: Integer; const SettingsFile: string);
begin
  inherited Create;
  if PixelScale < 1 then
    PixelScale := 1;
  FScale := PixelScale;
  Model := TAlarmModel.Create(SettingsFile);
  Canvas := TPixelBuffer.Create(AlarmContentW * FScale, AlarmContentH(Model.Expanded) * FScale);
  FNeedsPresent := True; { first frame, before the timer, so the window is not blank }
  FWantsResize := False;
  Model.ClearDirty;
end;

destructor TAlarmController.Destroy;
begin
  Canvas.Free;
  Model.Free;
  inherited Destroy;
end;

procedure TAlarmController.NoteChanges;
begin
  if Model.Dirty then
  begin
    FNeedsPresent := True;
    Model.ClearDirty;
  end;
  if Model.TakeChromeChange then
  begin
    { State change: the lever moved. The host reads WantsResize and
      changes the window height, then calls ApplyChrome. }
    FWantsResize := True;
    FNeedsPresent := True;
  end;
end;

procedure TAlarmController.Tick;
begin
  Model.SyncFromSystem;
  Model.PulseBlink;
  NoteChanges;
end;

function TAlarmController.PointerDown(X, Y: Integer): Boolean;
var
  Lay: TAlarmLayout;
  Hit: THitKind;
begin
  Result := False;
  if (X < 0) or (Y < 0) then
    Exit;
  Lay := BuildLayout(Model.Snapshot);
  Hit := HitTest(Lay, X, Y);
  case Hit of
    hitNone:
      begin
        { Empty face. The host starts a window drag. }
        Result := True;
        Exit;
      end;
    hitClose:
      begin
        { State change: drawn close mark. No system title bar to click. }
        Model.CommitForClose;
        FWantsQuit := True;
        Exit;
      end;
    hitLever: Model.ToggleLever;
    hitSwitch: Model.ToggleSwitch;
    hitDateIcon: Model.SelectRow(rowDate);
    hitTimeIcon: Model.SelectRow(rowTime);
    hitAlarmIcon: Model.SelectRow(rowAlarm);
    hitArrowUp: Model.Nudge(1);
    hitArrowDown: Model.Nudge(-1);
    hitDateMonth: Model.SelectDatePart(partMonth);
    hitDateDay: Model.SelectDatePart(partDay);
    hitDateYear: Model.SelectDatePart(partYear);
    hitTimeHour: Model.SelectTimePart(partHour);
    hitTimeMinute: Model.SelectTimePart(partMinute);
    hitTimeSecond: Model.SelectTimePart(partSecond);
    hitTimeAmPm: Model.SelectTimePart(partAmPm);
    hitAlarmHour: Model.SelectAlarmPart(partHour);
    hitAlarmMinute: Model.SelectAlarmPart(partMinute);
    hitAlarmSecond: Model.SelectAlarmPart(partSecond);
    hitAlarmAmPm: Model.SelectAlarmPart(partAmPm);
  end;
  NoteChanges;
end;

procedure TAlarmController.Key(Kind: TAlarmKeyKind; Extra: Integer);
begin
  case Kind of
    akUp: Model.Nudge(1);
    akDown: Model.Nudge(-1);
    akLeft: Model.MovePart(-1);
    akRight: Model.MovePart(1);
    akDigit: Model.TypeDigit(Extra);
    akLetter: Model.TypeLetter(Char(Extra));
    akTab:
      begin
        if not Model.Expanded then
          Model.ToggleLever;
        { Date → clock → alarm → date. Leaving the alarm row arms it. }
        case Model.Row of
          rowNone, rowAlarm: Model.SelectRow(rowDate);
          rowDate: Model.SelectRow(rowTime);
          rowTime: Model.SelectRow(rowAlarm);
        end;
      end;
    akEscape, akReturn:
      if Model.Expanded then
        Model.ToggleLever; { closes the panel and commits a pending alarm }
  end;
  NoteChanges;
end;

procedure TAlarmController.Render;
begin
  RenderAlarm(Canvas, Model.Snapshot, FScale);
end;

procedure TAlarmController.ApplyChrome;
var
  W, H: Integer;
begin
  W := AlarmContentW * FScale;
  H := AlarmContentH(Model.Expanded) * FScale;
  if (Canvas.Width <> W) or (Canvas.Height <> H) then
    Canvas.Resize(W, H);
  FWantsResize := False;
  Model.TakeChromeChange;
  FNeedsPresent := True;
end;

procedure TAlarmController.CommitForClose;
begin
  Model.CommitForClose;
end;

function TAlarmController.ConsumeBeep: Boolean;
begin
  Result := Model.ConsumeBeep;
end;

function TAlarmController.WantsCrosshair(X, Y: Integer): Boolean;
var
  Lay: TAlarmLayout;
begin
  if not Model.Expanded then
    Exit(False);
  Lay := BuildLayout(Model.Snapshot);
  { The numbers being edited are the line under the time. }
  Result := (Y >= Lay.AlarmRowTop) and (Y < Lay.AlarmRowTop + Lay.RowHeight);
end;

function TAlarmController.ContentWidth: Integer;
begin
  Result := AlarmContentW;
end;

function TAlarmController.ContentHeight: Integer;
begin
  Result := AlarmContentH(Model.Expanded);
end;

procedure TAlarmController.ConsumePresent;
begin
  FNeedsPresent := False;
end;

end.
