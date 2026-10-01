unit ualarmmodel;

{$mode objfpc}{$H+}

{ The Alarm Clock desk accessory's behaviour, with no pixels and no window.

  States of the alarm itself:

    off       switch down. Nothing is waiting.
    editing   switch up while the alarm row is selected. Not live yet.
    armed     switch up, and the user has left that row (or closed the
              lever, or closed the window). Waiting for the clock to cross
              the alarm time.
    ringing   the cross happened. One beep. The face keeps blinking until
              the switch is turned down.

  The 1990 Macintosh LC manual is blunt about the editing rule: the alarm
  will not go off unless you close the lever, select another area, or
  click the close box. FinishAlarmEdit is that rule.

  Setting the date or the time updates FOffsetSec. The original desk
  accessory wrote the Mac's clock chip (SetDateTime). This tribute never
  does that — Sonoma, Catalina, Windows, and the Pi keep their own clocks. }

interface

type
  TRowKind = (rowNone, rowDate, rowTime, rowAlarm);
  TTimePart = (partHour, partMinute, partSecond, partAmPm);
  TDatePart = (partMonth, partDay, partYear);

  TWall = record
    Year, Month, Day: Word;
    Hour24, Minute, Second: Word;
  end;

  { A snapshot the painter can draw without calling back into the model. }
  TAlarmView = record
    Expanded: Boolean;
    SwitchUp: Boolean;
    Committed: Boolean;
    Ringing: Boolean;
    BlinkOn: Boolean;
    UsingOffset: Boolean;
    Row: TRowKind;
    { True once a digit on the line is open. The picture alone does not set it. }
    Editing: Boolean;
    TimePart: TTimePart;
    AlarmPart: TTimePart;
    DatePart: TDatePart;
    Year, Month, Day: Word;
    Hour12, Minute, Second: Word;
    IsPM: Boolean;
    AlarmH, AlarmM, AlarmS: Word;
    AlarmPM: Boolean;
    { Digits typed so far for the active part. Empty means "show the value". }
    Typing: string;
  end;

  TAlarmModel = class
  private
    FSettings: string;
    FOffsetSec: Int64;
    FFrozen: Boolean;
    FExpanded: Boolean;
    FRow: TRowKind;
    FEditing: Boolean;
    FTimePart: TTimePart;
    FAlarmPart: TTimePart;
    FDatePart: TDatePart;
    FSwitchUp: Boolean;
    FCommitted: Boolean;
    FRinging: Boolean;
    FBlinkOn: Boolean;
    FBlinkTick: Integer;
    FBeep: Boolean;
    FDirty: Boolean;
    FChromeChanged: Boolean;
    FHavePrev: Boolean;
    FPrevSOD: Integer;
    FDisplay: TWall;
    FAlarmH, FAlarmM, FAlarmS: Word;
    FAlarmPM: Boolean;
    FTyping: string;
    procedure ApplyDisplay(const W: TWall);
    procedure Sample;
    procedure FinishAlarmEdit;
    procedure SetDisplayedWall(const W: TWall);
    procedure NudgeDate(Delta: Integer);
    procedure NudgeClock(Delta: Integer);
    procedure NudgeAlarm(Delta: Integer);
    procedure PutClockHour(H12: Word);
    procedure PutClockMinute(M: Word);
    procedure PutClockSecond(S: Word);
    procedure PutClockPM(PM: Boolean);
    procedure PutAlarmHour(H12: Word);
    procedure PutAlarmMinute(M: Word);
    procedure PutAlarmSecond(S: Word);
    procedure PutAlarmPM(PM: Boolean);
    procedure TypeClockDigit(D: Integer);
    procedure TypeDateDigit(D: Integer);
    procedure LoadSettings;
    procedure SaveSettings;
  public
    constructor Create(const SettingsFile: string);
    destructor Destroy; override;
    procedure SyncFromSystem;
    procedure PulseBlink;
    procedure ToggleLever;
    procedure ToggleSwitch;
    procedure SelectRow(ARow: TRowKind);
    procedure SelectDatePart(APart: TDatePart);
    procedure SelectTimePart(APart: TTimePart);
    procedure SelectAlarmPart(APart: TTimePart);
    procedure Nudge(Delta: Integer);
    procedure TypeDigit(D: Integer);
    procedure TypeLetter(Ch: Char);
    procedure MovePart(Delta: Integer);
    procedure CommitForClose;
    procedure ResetToSystem;
    procedure FreezeAt(Year, Month, Day, Hour24, Minute, Second: Word);
    procedure SetAlarmTime(H12, M, S: Word; PM: Boolean);
    procedure AdvanceSeconds(N: Integer);
    procedure Pose(AExpanded: Boolean; const Display: TWall;
      AH, AM, ASec: Word; APM, ASwitch, ACommitted, ARinging, ABlink: Boolean;
      ARow: TRowKind; ADatePart: TDatePart; ATimePart, AAlarmPart: TTimePart);
    function ConsumeBeep: Boolean;
    function TakeChromeChange: Boolean;
    procedure ClearDirty;
    function Snapshot: TAlarmView;
    property Expanded: Boolean read FExpanded;
    property Ringing: Boolean read FRinging;
    property Committed: Boolean read FCommitted;
    property SwitchUp: Boolean read FSwitchUp;
    property Dirty: Boolean read FDirty;
    property Frozen: Boolean read FFrozen;
    property Row: TRowKind read FRow;
    property OffsetSeconds: Int64 read FOffsetSec;
  end;

{ True when the displayed clock moved forward across TargetSOD.
  A backward edit (nudging the minute down) is not a midnight wrap. }
function AlarmCrossed(PrevSOD, CurrSOD, TargetSOD: Integer): Boolean;

{ 1..12 plus an AM/PM flag. 12 AM is midnight (hour 0), 12 PM is noon. }
function Hour24Of(H12: Word; PM: Boolean): Word;
function Hour12Of(Hour24: Word): Word;
function IsAfternoon(Hour24: Word): Boolean;
function DaysInMonth(Year, Month: Word): Word;

implementation

uses
  SysUtils;

const
  { System 7's Alarm Clock refused years outside 1921..2020 (the same
    family of limit as the classic Mac's 2020 date bug, later fixed in
    the Mac OS 9.0.4 Date & Time panel). A machine today is already past
    2020, so the tribute allows a nudge through 2099 and still refuses
    to walk back before 1921. }
  YearMin = 1921;
  YearMax = 2099;
  HalfDay = 12 * 3600;

function DaysInMonth(Year, Month: Word): Word;
const
  Lengths: array[1..12] of Word = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  if (Month < 1) or (Month > 12) then
    Exit(30);
  Result := Lengths[Month];
  if (Month = 2) and ((Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0))) then
    Result := 29;
end;

function Hour12Of(Hour24: Word): Word;
begin
  Result := Hour24 mod 12;
  if Result = 0 then
    Result := 12;
end;

function IsAfternoon(Hour24: Word): Boolean;
begin
  Result := Hour24 >= 12;
end;

function Hour24Of(H12: Word; PM: Boolean): Word;
begin
  Result := H12 mod 12; { 12 → 0, which is midnight or noon before PM is applied }
  if PM then
    Inc(Result, 12);
end;

function SecondsOfDay(Hour24, Minute, Second: Word): Integer;
begin
  Result := Integer(Hour24) * 3600 + Integer(Minute) * 60 + Integer(Second);
end;

function AlarmCrossed(PrevSOD, CurrSOD, TargetSOD: Integer): Boolean;
var
  Forward: Boolean;
begin
  if PrevSOD = CurrSOD then
    Exit(False);
  { A 10 Hz tick moves one second forward. Setting the clock back also
    makes Curr < Prev, and that must not look like midnight.
    Forward across midnight is a jump of more than half a day backward
    on the raw numbers (23:59 → 00:00). }
  if CurrSOD > PrevSOD then
    Forward := (CurrSOD - PrevSOD) <= HalfDay
  else
    Forward := (PrevSOD - CurrSOD) > HalfDay;
  if not Forward then
    Exit(False);
  if CurrSOD > PrevSOD then
    Result := (TargetSOD > PrevSOD) and (TargetSOD <= CurrSOD)
  else
    Result := (TargetSOD > PrevSOD) or (TargetSOD <= CurrSOD);
end;

function SameWall(const A, B: TWall): Boolean;
begin
  Result := (A.Year = B.Year) and (A.Month = B.Month) and (A.Day = B.Day) and
    (A.Hour24 = B.Hour24) and (A.Minute = B.Minute) and (A.Second = B.Second);
end;

procedure ClampDay(var W: TWall);
var
  Last: Word;
begin
  Last := DaysInMonth(W.Year, W.Month);
  if W.Day > Last then
    W.Day := Last;
  if W.Day < 1 then
    W.Day := 1;
end;

function TryEncodeWall(const W: TWall; out DT: TDateTime): Boolean;
begin
  Result := False;
  if (W.Year < 1) or (W.Year > 9999) then
    Exit;
  if (W.Month < 1) or (W.Month > 12) then
    Exit;
  if (W.Day < 1) or (W.Day > DaysInMonth(W.Year, W.Month)) then
    Exit;
  if (W.Hour24 > 23) or (W.Minute > 59) or (W.Second > 59) then
    Exit;
  try
    DT := EncodeDate(W.Year, W.Month, W.Day) +
      EncodeTime(W.Hour24, W.Minute, W.Second, 0);
    Result := True;
  except
    Result := False;
  end;
end;

constructor TAlarmModel.Create(const SettingsFile: string);
begin
  inherited Create;
  FSettings := SettingsFile;
  FAlarmH := 12;
  FAlarmM := 0;
  FAlarmS := 0;
  FAlarmPM := False;
  FSwitchUp := False;
  FCommitted := False;
  FExpanded := False;
  FRow := rowNone;
  FEditing := False;
  FTimePart := partHour;
  FAlarmPart := partHour;
  FDatePart := partMonth;
  FBlinkOn := False;
  FRinging := False;
  FFrozen := False;
  FHavePrev := False;
  FDirty := True;
  LoadSettings;
  { First sample establishes "where the hands were". It must not ring
    just because the program was opened on the alarm second. }
  Sample;
end;

destructor TAlarmModel.Destroy;
begin
  SaveSettings;
  inherited Destroy;
end;

procedure TAlarmModel.LoadSettings;
var
  F: TextFile;
  Line, Key: string;
  P, Val: Integer;
begin
  if (FSettings = '') or (not FileExists(FSettings)) then
    Exit;
  try
    AssignFile(F, FSettings);
    Reset(F);
    try
      while not Eof(F) do
      begin
        ReadLn(F, Line);
        P := Pos('=', Line);
        if P < 2 then
          Continue;
        Key := LowerCase(Trim(Copy(Line, 1, P - 1)));
        Val := StrToIntDef(Trim(Copy(Line, P + 1, 40)), -1);
        if Key = 'hour' then
        begin
          if (Val >= 1) and (Val <= 12) then
            FAlarmH := Val;
        end
        else if Key = 'minute' then
        begin
          if (Val >= 0) and (Val <= 59) then
            FAlarmM := Val;
        end
        else if Key = 'second' then
        begin
          if (Val >= 0) and (Val <= 59) then
            FAlarmS := Val;
        end
        else if Key = 'pm' then
          FAlarmPM := Val = 1
        else if Key = 'switch' then
          FSwitchUp := Val = 1;
      end;
    finally
      CloseFile(F);
    end;
    { A fresh process is never mid-edit. Switch up means the alarm is live. }
    FCommitted := FSwitchUp;
  except
    { A broken prefs file must not stop the clock. Defaults stand. }
  end;
end;

procedure TAlarmModel.SaveSettings;
var
  F: TextFile;
  Dir: string;
begin
  if FSettings = '' then
    Exit;
  try
    Dir := ExtractFilePath(FSettings);
    if Dir <> '' then
      ForceDirectories(Dir);
    AssignFile(F, FSettings);
    Rewrite(F);
    try
      WriteLn(F, 'hour=', FAlarmH);
      WriteLn(F, 'minute=', FAlarmM);
      WriteLn(F, 'second=', FAlarmS);
      WriteLn(F, 'pm=', Ord(FAlarmPM));
      WriteLn(F, 'switch=', Ord(FSwitchUp));
    finally
      CloseFile(F);
    end;
  except
    { The clock still runs if the config directory is not writable. }
  end;
end;

procedure TAlarmModel.ApplyDisplay(const W: TWall);
var
  SOD, Target: Integer;
  Fired: Boolean;
begin
  Fired := False;
  SOD := SecondsOfDay(W.Hour24, W.Minute, W.Second);
  if FHavePrev and FCommitted and (not FRinging) then
  begin
    Target := SecondsOfDay(Hour24Of(FAlarmH, FAlarmPM), FAlarmM, FAlarmS);
    if AlarmCrossed(FPrevSOD, SOD, Target) then
    begin
      { State change: armed → ringing. One beep, then the face blinks
        until the switch is turned down. It does not beep every second. }
      FRinging := True;
      FBlinkOn := True;
      FBlinkTick := 0;
      FBeep := True;
      Fired := True;
    end;
  end;
  if (not SameWall(FDisplay, W)) or Fired then
    FDirty := True;
  FDisplay := W;
  FPrevSOD := SOD;
  FHavePrev := True;
end;

procedure TAlarmModel.Sample;
var
  DT: TDateTime;
  W: TWall;
  MS: Word;
begin
  if FFrozen then
    Exit;
  try
    DT := Now + FOffsetSec / SecsPerDay;
    DecodeDate(DT, W.Year, W.Month, W.Day);
    DecodeTime(DT, W.Hour24, W.Minute, W.Second, MS);
  except
    Exit;
  end;
  ApplyDisplay(W);
end;

procedure TAlarmModel.SyncFromSystem;
begin
  Sample;
end;

procedure TAlarmModel.PulseBlink;
begin
  if not FRinging then
    Exit;
  Inc(FBlinkTick);
  if FBlinkTick < 5 then
    Exit;
  FBlinkTick := 0;
  { State change: blink phase. The original alternated the Apple mark
    with an alarm-clock icon in the menu bar, about twice a second.
    We don't own that menu, so the time plaque inverts instead. }
  FBlinkOn := not FBlinkOn;
  FDirty := True;
end;

procedure TAlarmModel.SetDisplayedWall(const W: TWall);
var
  Want: TDateTime;
  Safe: TWall;
begin
  Safe := W;
  ClampDay(Safe);
  if FFrozen then
  begin
    { Tests and the snapshot poses step the clock without Now(). }
    ApplyDisplay(Safe);
    Exit;
  end;
  if not TryEncodeWall(Safe, Want) then
    Exit;
  { State change: session offset. Want is the wall time the user just
    set; the OS clock stays where it is. The next Sample keeps counting
    from here. }
  FOffsetSec := Round((Want - SysUtils.Now) * SecsPerDay);
  ApplyDisplay(Safe);
end;

procedure TAlarmModel.FinishAlarmEdit;
begin
  FTyping := '';
  if FSwitchUp then
  begin
    if not FCommitted then
    begin
      { State change: editing → armed. The manual's "leave the control". }
      FCommitted := True;
    end;
  end
  else
  begin
    FCommitted := False;
    if FRinging then
    begin
      { State change: ringing → off, because the knob is down. }
      FRinging := False;
    end;
  end;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.ToggleLever;
begin
  FTyping := '';
  if FExpanded then
  begin
    if FRow = rowAlarm then
      FinishAlarmEdit;
    FRow := rowNone;
    { State change: expanded panel → compact clock. The host shrinks
      the window to match. The lever points up again. }
    FExpanded := False;
  end
  else
  begin
    { State change: compact → expanded. The lever points down and the
      date is the line on show, so the middle picture is the one lit. }
    FExpanded := True;
    if FRow = rowNone then
      SelectRow(rowDate);
  end;
  FChromeChanged := True;
  FDirty := True;
end;

procedure TAlarmModel.ToggleSwitch;
begin
  FTyping := '';
  FSwitchUp := not FSwitchUp;
  if FSwitchUp then
  begin
    if FRow = rowAlarm then
    begin
      { State change: knob up, but the alarm row is still selected, so
        the alarm is not live. Closing the lever (or picking another
        row, or closing the window) is what arms it. }
      FCommitted := False;
    end
    else
    begin
      { State change: knob up while that row is not being edited → armed. }
      FCommitted := True;
    end;
  end
  else
  begin
    { State change: knob down. Disarm, and stop the blink immediately.
      The manual: click the button again to turn the alarm off. }
    FCommitted := False;
    FRinging := False;
    FBeep := False;
  end;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.SelectRow(ARow: TRowKind);
begin
  if (ARow = rowNone) or (ARow = FRow) then
    Exit;
  if FRow = rowAlarm then
    FinishAlarmEdit;
  { State change: which of the three areas is highlighted. }
  FRow := ARow;
  FTyping := '';
  case ARow of
    rowDate: FDatePart := partMonth;
    rowTime: FTimePart := partHour;
    rowAlarm:
      begin
        FAlarmPart := partHour;
        { State change: opening the alarm row suspends a live alarm so
          it cannot fire while its digits are being changed. }
        FCommitted := False;
      end;
  end;
  { The picture is lit. Digits stay plain until one of them is chosen. }
  FEditing := False;
  FDirty := True;
end;

procedure TAlarmModel.SelectDatePart(APart: TDatePart);
begin
  if FRow <> rowDate then
    SelectRow(rowDate);
  FEditing := True;
  if FDatePart = APart then
    Exit;
  FTyping := '';
  FDatePart := APart;
  FDirty := True;
end;

procedure TAlarmModel.SelectTimePart(APart: TTimePart);
begin
  if FRow <> rowTime then
    SelectRow(rowTime);
  FEditing := True;
  if FTimePart = APart then
    Exit;
  FTyping := '';
  FTimePart := APart;
  FDirty := True;
end;

procedure TAlarmModel.SelectAlarmPart(APart: TTimePart);
begin
  if FRow <> rowAlarm then
    SelectRow(rowAlarm);
  FEditing := True;
  if FAlarmPart = APart then
    Exit;
  FTyping := '';
  FAlarmPart := APart;
  FDirty := True;
end;

procedure TAlarmModel.PutClockHour(H12: Word);
var
  W: TWall;
begin
  if (H12 < 1) or (H12 > 12) then
    Exit;
  W := FDisplay;
  { AM/PM is its own part. 11 AM nudged to 12 stays AM (midnight),
    which is how the separate fields on the original clock worked. }
  W.Hour24 := Hour24Of(H12, IsAfternoon(W.Hour24));
  SetDisplayedWall(W);
end;

procedure TAlarmModel.PutClockMinute(M: Word);
var
  W: TWall;
begin
  if M > 59 then
    Exit;
  W := FDisplay;
  W.Minute := M;
  SetDisplayedWall(W);
end;

procedure TAlarmModel.PutClockSecond(S: Word);
var
  W: TWall;
begin
  if S > 59 then
    Exit;
  W := FDisplay;
  W.Second := S;
  SetDisplayedWall(W);
end;

procedure TAlarmModel.PutClockPM(PM: Boolean);
var
  W: TWall;
begin
  W := FDisplay;
  W.Hour24 := Hour24Of(Hour12Of(W.Hour24), PM);
  SetDisplayedWall(W);
end;

procedure TAlarmModel.PutAlarmHour(H12: Word);
begin
  if (H12 < 1) or (H12 > 12) then
    Exit;
  FAlarmH := H12;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.PutAlarmMinute(M: Word);
begin
  if M > 59 then
    Exit;
  FAlarmM := M;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.PutAlarmSecond(S: Word);
begin
  if S > 59 then
    Exit;
  FAlarmS := S;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.PutAlarmPM(PM: Boolean);
begin
  if FAlarmPM = PM then
    Exit;
  FAlarmPM := PM;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.NudgeDate(Delta: Integer);
var
  W: TWall;
  M, D, Y, Last: Integer;
begin
  W := FDisplay;
  case FDatePart of
    partMonth:
      begin
        M := Integer(W.Month) + Delta;
        while M > 12 do
          Dec(M, 12);
        while M < 1 do
          Inc(M, 12);
        W.Month := M;
        { 31 March nudged to February cannot stay the 31st. }
        ClampDay(W);
      end;
    partDay:
      begin
        Last := DaysInMonth(W.Year, W.Month);
        D := Integer(W.Day) + Delta;
        if D > Last then
          D := 1;
        if D < 1 then
          D := Last;
        W.Day := D;
      end;
    partYear:
      begin
        Y := Integer(W.Year) + Delta;
        if Y < YearMin then
          Y := YearMin;
        if Y > YearMax then
          Y := YearMax;
        W.Year := Y;
        ClampDay(W);
      end;
  end;
  SetDisplayedWall(W);
end;

procedure TAlarmModel.NudgeClock(Delta: Integer);
var
  H, M, S: Integer;
begin
  case FTimePart of
    partHour:
      begin
        H := Integer(Hour12Of(FDisplay.Hour24)) + Delta;
        if H > 12 then
          H := 1;
        if H < 1 then
          H := 12;
        PutClockHour(H);
      end;
    partMinute:
      begin
        M := Integer(FDisplay.Minute) + Delta;
        if M > 59 then
          M := 0;
        if M < 0 then
          M := 59;
        PutClockMinute(M);
      end;
    partSecond:
      begin
        S := Integer(FDisplay.Second) + Delta;
        if S > 59 then
          S := 0;
        if S < 0 then
          S := 59;
        PutClockSecond(S);
      end;
    partAmPm:
      PutClockPM(not IsAfternoon(FDisplay.Hour24));
  end;
end;

procedure TAlarmModel.NudgeAlarm(Delta: Integer);
var
  H, M, S: Integer;
begin
  case FAlarmPart of
    partHour:
      begin
        H := Integer(FAlarmH) + Delta;
        if H > 12 then
          H := 1;
        if H < 1 then
          H := 12;
        PutAlarmHour(H);
      end;
    partMinute:
      begin
        M := Integer(FAlarmM) + Delta;
        if M > 59 then
          M := 0;
        if M < 0 then
          M := 59;
        PutAlarmMinute(M);
      end;
    partSecond:
      begin
        S := Integer(FAlarmS) + Delta;
        if S > 59 then
          S := 0;
        if S < 0 then
          S := 59;
        PutAlarmSecond(S);
      end;
    partAmPm:
      PutAlarmPM(not FAlarmPM);
  end;
end;

procedure TAlarmModel.Nudge(Delta: Integer);
begin
  if (Delta = 0) or (FRow = rowNone) then
    Exit;
  FEditing := True;
  FTyping := '';
  case FRow of
    rowNone: Exit;
    rowDate: NudgeDate(Delta);
    rowTime: NudgeClock(Delta);
    rowAlarm: NudgeAlarm(Delta);
  end;
end;

procedure TAlarmModel.TypeClockDigit(D: Integer);
var
  Part: TTimePart;
  Tens: Integer;

  procedure AcceptHour(H: Word);
  begin
    if FRow = rowAlarm then
      PutAlarmHour(H)
    else
      PutClockHour(H);
  end;

  procedure AcceptMinute(M: Word);
  begin
    if FRow = rowAlarm then
      PutAlarmMinute(M)
    else
      PutClockMinute(M);
  end;

  procedure AcceptSecond(S: Word);
  begin
    if FRow = rowAlarm then
      PutAlarmSecond(S)
    else
      PutClockSecond(S);
  end;

begin
  if FRow = rowAlarm then
    Part := FAlarmPart
  else
    Part := FTimePart;
  case Part of
    partHour:
      begin
        { '1' may become 10, 11, or 12. Any other first digit is the hour. }
        if FTyping = '' then
        begin
          if D = 0 then
            Exit;
          if D = 1 then
          begin
            FTyping := '1';
            AcceptHour(1);
          end
          else
          begin
            FTyping := '';
            AcceptHour(D);
          end;
        end
        else
        begin
          if D <= 2 then
            AcceptHour(10 + D)
          else
            AcceptHour(D);
          FTyping := '';
        end;
      end;
    partMinute, partSecond:
      begin
        if FTyping = '' then
        begin
          if D <= 5 then
          begin
            FTyping := Char(Ord('0') + D);
            if Part = partMinute then
              AcceptMinute(D)
            else
              AcceptSecond(D);
          end
          else
          begin
            FTyping := '';
            if Part = partMinute then
              AcceptMinute(D)
            else
              AcceptSecond(D);
          end;
        end
        else
        begin
          Tens := Ord(FTyping[1]) - Ord('0');
          FTyping := '';
          if Part = partMinute then
            AcceptMinute(Tens * 10 + D)
          else
            AcceptSecond(Tens * 10 + D);
        end;
      end;
    partAmPm:
      Exit;
  end;
  FDirty := True;
end;

procedure TAlarmModel.TypeDateDigit(D: Integer);
var
  W: TWall;
  N, Tens: Integer;
begin
  W := FDisplay;
  case FDatePart of
    partMonth:
      begin
        if FTyping = '' then
        begin
          if D = 0 then
            Exit;
          if D = 1 then
          begin
            FTyping := '1';
            W.Month := 1;
            ClampDay(W);
            SetDisplayedWall(W);
          end
          else
          begin
            FTyping := '';
            W.Month := D;
            ClampDay(W);
            SetDisplayedWall(W);
          end;
        end
        else
        begin
          N := 10 + D;
          FTyping := '';
          if N > 12 then
            N := D;
          if N < 1 then
            Exit;
          W.Month := N;
          ClampDay(W);
          SetDisplayedWall(W);
        end;
      end;
    partDay:
      begin
        if FTyping = '' then
        begin
          if D = 0 then
            Exit;
          if D <= 3 then
          begin
            FTyping := Char(Ord('0') + D);
            W.Day := D;
            SetDisplayedWall(W);
          end
          else
          begin
            FTyping := '';
            if D <= DaysInMonth(W.Year, W.Month) then
            begin
              W.Day := D;
              SetDisplayedWall(W);
            end;
          end;
        end
        else
        begin
          Tens := Ord(FTyping[1]) - Ord('0');
          N := Tens * 10 + D;
          FTyping := '';
          if (N >= 1) and (N <= DaysInMonth(W.Year, W.Month)) then
          begin
            W.Day := N;
            SetDisplayedWall(W);
          end;
        end;
      end;
    partYear:
      begin
        { Don't jump the calendar to year 2 after the first key.
          Apply only when four digits land inside the allowed span. }
        if (FTyping = '') or (Length(FTyping) >= 4) then
          FTyping := Char(Ord('0') + D)
        else
          FTyping := FTyping + Char(Ord('0') + D);
        FDirty := True;
        if Length(FTyping) = 4 then
        begin
          N := StrToIntDef(FTyping, 0);
          FTyping := '';
          if (N >= YearMin) and (N <= YearMax) then
          begin
            W.Year := N;
            ClampDay(W);
            SetDisplayedWall(W);
          end;
        end;
      end;
  end;
end;

procedure TAlarmModel.TypeDigit(D: Integer);
begin
  if (D < 0) or (D > 9) or (FRow = rowNone) then
    Exit;
  FEditing := True;
  case FRow of
    rowTime, rowAlarm: TypeClockDigit(D);
    rowDate: TypeDateDigit(D);
  end;
end;

procedure TAlarmModel.TypeLetter(Ch: Char);
var
  PM: Boolean;
begin
  Ch := UpCase(Ch);
  if (Ch <> 'A') and (Ch <> 'P') then
    Exit;
  if (FRow <> rowTime) and (FRow <> rowAlarm) then
    Exit;
  FEditing := True;
  PM := Ch = 'P';
  FTyping := '';
  if FRow = rowAlarm then
  begin
    if FAlarmPart <> partAmPm then
      FAlarmPart := partAmPm;
    PutAlarmPM(PM);
  end
  else
  begin
    if FTimePart <> partAmPm then
      FTimePart := partAmPm;
    PutClockPM(PM);
  end;
end;

procedure TAlarmModel.MovePart(Delta: Integer);
begin
  if (Delta = 0) or (FRow = rowNone) then
    Exit;
  FEditing := True;
  FTyping := '';
  case FRow of
    rowNone: Exit;
    rowDate:
      FDatePart := TDatePart((Ord(FDatePart) + Delta + 3) mod 3);
    rowTime:
      FTimePart := TTimePart((Ord(FTimePart) + Delta + 4) mod 4);
    rowAlarm:
      FAlarmPart := TTimePart((Ord(FAlarmPart) + Delta + 4) mod 4);
  end;
  FDirty := True;
end;

procedure TAlarmModel.CommitForClose;
begin
  { State change: the close box. Same commit as closing the lever.
    The process is about to end; the saved switch is what the next
    launch arms. The original DA could keep ringing after its window
    closed because it lived in the system. This program cannot. }
  if FRow = rowAlarm then
  begin
    FRow := rowNone;
    FinishAlarmEdit;
  end
  else
    SaveSettings;
end;

procedure TAlarmModel.ResetToSystem;
begin
  { State change: throw away the session offset. HavePrev is cleared so
    the jump back to the real clock is not treated as crossing the alarm. }
  FOffsetSec := 0;
  FFrozen := False;
  FTyping := '';
  FHavePrev := False;
  Sample;
  FDirty := True;
end;

procedure TAlarmModel.FreezeAt(Year, Month, Day, Hour24, Minute, Second: Word);
var
  W: TWall;
begin
  FFrozen := True;
  FOffsetSec := 0;
  W.Year := Year;
  W.Month := Month;
  W.Day := Day;
  W.Hour24 := Hour24;
  W.Minute := Minute;
  W.Second := Second;
  FHavePrev := False;
  ApplyDisplay(W);
end;

procedure TAlarmModel.SetAlarmTime(H12, M, S: Word; PM: Boolean);
begin
  if (H12 < 1) or (H12 > 12) then
    Exit;
  if (M > 59) or (S > 59) then
    Exit;
  FAlarmH := H12;
  FAlarmM := M;
  FAlarmS := S;
  FAlarmPM := PM;
  FDirty := True;
  SaveSettings;
end;

procedure TAlarmModel.AdvanceSeconds(N: Integer);
var
  I: Integer;
  DT: TDateTime;
  W: TWall;
  MS: Word;
begin
  { One second at a time so a crossing in the middle of the jump is seen.
    Frozen only — the live clock advances by Sample. }
  if not FFrozen then
    Exit;
  for I := 1 to N do
  begin
    if not TryEncodeWall(FDisplay, DT) then
      Exit;
    DT := DT + 1 / SecsPerDay;
    DecodeDate(DT, W.Year, W.Month, W.Day);
    DecodeTime(DT, W.Hour24, W.Minute, W.Second, MS);
    ApplyDisplay(W);
  end;
end;

procedure TAlarmModel.Pose(AExpanded: Boolean; const Display: TWall;
  AH, AM, ASec: Word; APM, ASwitch, ACommitted, ARinging, ABlink: Boolean;
  ARow: TRowKind; ADatePart: TDatePart; ATimePart, AAlarmPart: TTimePart);
begin
  { Fixture for snapshots. Not a user gesture — it plants every flag. }
  FFrozen := True;
  FOffsetSec := 0;
  FExpanded := AExpanded;
  FDisplay := Display;
  FAlarmH := AH;
  FAlarmM := AM;
  FAlarmS := ASec;
  FAlarmPM := APM;
  FSwitchUp := ASwitch;
  FCommitted := ACommitted;
  FRinging := ARinging;
  FBlinkOn := ABlink;
  FRow := ARow;
  FEditing := False;
  FDatePart := ADatePart;
  FTimePart := ATimePart;
  FAlarmPart := AAlarmPart;
  FTyping := '';
  FDirty := True;
  FChromeChanged := True;
  FHavePrev := True;
  FPrevSOD := SecondsOfDay(Display.Hour24, Display.Minute, Display.Second);
end;

function TAlarmModel.ConsumeBeep: Boolean;
begin
  Result := FBeep;
  FBeep := False;
end;

function TAlarmModel.TakeChromeChange: Boolean;
begin
  Result := FChromeChanged;
  FChromeChanged := False;
end;

procedure TAlarmModel.ClearDirty;
begin
  FDirty := False;
end;

function TAlarmModel.Snapshot: TAlarmView;
begin
  Result.Expanded := FExpanded;
  Result.SwitchUp := FSwitchUp;
  Result.Committed := FCommitted;
  Result.Ringing := FRinging;
  Result.BlinkOn := FBlinkOn;
  Result.UsingOffset := (not FFrozen) and (FOffsetSec <> 0);
  Result.Row := FRow;
  Result.Editing := FEditing;
  Result.TimePart := FTimePart;
  Result.AlarmPart := FAlarmPart;
  Result.DatePart := FDatePart;
  Result.Year := FDisplay.Year;
  Result.Month := FDisplay.Month;
  Result.Day := FDisplay.Day;
  Result.Hour12 := Hour12Of(FDisplay.Hour24);
  Result.Minute := FDisplay.Minute;
  Result.Second := FDisplay.Second;
  Result.IsPM := IsAfternoon(FDisplay.Hour24);
  Result.AlarmH := FAlarmH;
  Result.AlarmM := FAlarmM;
  Result.AlarmS := FAlarmS;
  Result.AlarmPM := FAlarmPM;
  Result.Typing := FTyping;
end;

end.
