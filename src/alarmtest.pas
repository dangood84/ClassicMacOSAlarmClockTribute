program alarmtest;

{$mode objfpc}{$H+}

{ Headless checks for the alarm state machine, the crossing rule, and
  a couple of layout hits. No window. }

uses
  SysUtils, ualarmmodel, ualarmrender, ualarmapp;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

procedure Expect(const LabelText: string; Got, Want: Boolean);
begin
  if Got <> Want then
    Fail(LabelText);
  WriteLn('ok   ', LabelText);
end;

procedure ExpectInt(const LabelText: string; Got, Want: Integer);
begin
  if Got <> Want then
    Fail(LabelText + ': got ' + IntToStr(Got) + ' want ' + IntToStr(Want));
  WriteLn('ok   ', LabelText);
end;

procedure ExpectWord(const LabelText: string; Got, Want: Word);
begin
  ExpectInt(LabelText, Got, Want);
end;

function NextHour12(H: Word): Word;
begin
  Result := H + 1;
  if Result > 12 then
    Result := 1;
end;

var
  M: TAlarmModel;
  V: TAlarmView;
  Lay: TAlarmLayout;
  BeforeH: Word;
  BeforePM: Boolean;
  BeforeMin: Word;
  Path: string;
  Buf: TPixelBuffer;
  N, Black, I: Integer;
  P: PByte;
  CX, CY: Integer;
begin
  Expect('12 AM is midnight', Hour24Of(12, False) = 0, True);
  Expect('12 PM is noon', Hour24Of(12, True) = 12, True);
  Expect('1 PM is 13', Hour24Of(1, True) = 13, True);
  Expect('hour 0 displays 12', Hour12Of(0) = 12, True);
  Expect('hour 15 displays 3', Hour12Of(15) = 3, True);
  Expect('Feb 2024 has 29', DaysInMonth(2024, 2) = 29, True);
  Expect('Feb 2026 has 28', DaysInMonth(2026, 2) = 28, True);
  Expect('Apr has 30', DaysInMonth(2026, 4) = 30, True);

  Expect('forward cross', AlarmCrossed(100, 105, 103), True);
  Expect('exact curr counts', AlarmCrossed(100, 105, 105), True);
  Expect('same second is not a cross', AlarmCrossed(100, 100, 100), False);
  Expect('backward nudge is not midnight', AlarmCrossed(28800, 28740, 82800), False);
  Expect('midnight wrap hits 00:00', AlarmCrossed(86399, 1, 0), True);
  Expect('midnight wrap misses the afternoon', AlarmCrossed(86399, 1, 40000), False);

  M := TAlarmModel.Create('');
  try
    M.FreezeAt(2026, 10, 1, 6, 59, 58);
    M.SetAlarmTime(7, 0, 0, False);
    M.ToggleSwitch; { row is none, so the knob arms immediately }
    Expect('switch up is committed', M.Committed, True);
    M.AdvanceSeconds(1);
    Expect('6:59:59 has not rung', M.Ringing, False);
    M.AdvanceSeconds(1);
    Expect('7:00:00 rings', M.Ringing, True);
    Expect('one beep', M.ConsumeBeep, True);
    M.AdvanceSeconds(3);
    Expect('no second beep', M.ConsumeBeep, False);
    Expect('still blinking', M.Ringing, True);
    M.ToggleSwitch;
    Expect('knob down stops the blink', M.Ringing, False);
    Expect('knob down disarms', M.Committed, False);
  finally
    M.Free;
  end;

  M := TAlarmModel.Create('');
  try
    { Editing the alarm row suspends it, even if the knob is up. }
    M.FreezeAt(2026, 10, 1, 6, 59, 58);
    M.SetAlarmTime(7, 0, 0, False);
    M.SelectRow(rowAlarm);
    M.ToggleSwitch;
    Expect('editing is not live', M.Committed, False);
    M.AdvanceSeconds(5);
    Expect('does not ring mid-edit', M.Ringing, False);
    M.ToggleLever; { was not expanded; this OPENS the lever }
    { Already on the alarm row, so opening does not switch to the date. }
    Expect('first lever opens', M.Expanded, True);
    Expect('open keeps the alarm row', M.Row = rowAlarm, True);
    M.ToggleLever;
    Expect('second lever commits', M.Committed, True);
    M.ToggleLever;
    Expect('opening from the compact face lights the date', M.Row = rowDate, True);
    Expect('the date picture is lit, not a digit', M.Snapshot.Editing, False);
    Expect('already past 7:00, so quiet', M.Ringing, False);
  finally
    M.Free;
  end;

  M := TAlarmModel.Create('');
  try
    M.FreezeAt(2026, 10, 1, 23, 59, 59);
    M.SetAlarmTime(12, 0, 0, False); { midnight }
    M.ToggleSwitch;
    M.AdvanceSeconds(1);
    V := M.Snapshot;
    Expect('wrapped to the next day', V.Day = 2, True);
    Expect('midnight alarm rang', M.Ringing, True);
  finally
    M.Free;
  end;

  M := TAlarmModel.Create('');
  try
    { 29 Feb 2024 nudged to 2025 must not stay the 29th. }
    M.FreezeAt(2024, 2, 29, 10, 0, 0);
    M.SelectDatePart(partYear);
    M.Nudge(1);
    V := M.Snapshot;
    ExpectWord('year', V.Year, 2025);
    ExpectWord('clamped day', V.Day, 28);
    ExpectWord('still February', V.Month, 2);
  finally
    M.Free;
  end;

  M := TAlarmModel.Create('');
  try
    { Separate fields: 11 AM's hour goes to 12 and stays AM. }
    M.FreezeAt(2026, 10, 1, 11, 15, 0);
    M.SelectTimePart(partHour);
    M.Nudge(1);
    V := M.Snapshot;
    ExpectWord('11 AM hour becomes 12', V.Hour12, 12);
    Expect('stays AM', V.IsPM, False);
    M.SelectTimePart(partAmPm);
    M.Nudge(1);
    V := M.Snapshot;
    Expect('AM flips to PM', V.IsPM, True);
    ExpectWord('hour digits stay 12', V.Hour12, 12);
  finally
    M.Free;
  end;

  M := TAlarmModel.Create('');
  try
    M.FreezeAt(2026, 10, 1, 8, 0, 0);
    M.SelectAlarmPart(partHour);
    M.TypeDigit(1);
    M.TypeDigit(0);
    V := M.Snapshot;
    ExpectWord('typed alarm hour', V.AlarmH, 10);
    M.SelectTimePart(partMinute);
    M.TypeDigit(1);
    M.TypeDigit(5);
    V := M.Snapshot;
    ExpectWord('typed minute', V.Minute, 15);
  finally
    M.Free;
  end;

  { Live clock: nudging the hour moves it by one and keeps AM/PM.
    This talks to Now(), but only checks the relative change. }
  M := TAlarmModel.Create('');
  try
    V := M.Snapshot;
    BeforeH := V.Hour12;
    BeforePM := V.IsPM;
    BeforeMin := V.Minute;
    M.SelectTimePart(partHour);
    M.Nudge(1);
    V := M.Snapshot;
    ExpectWord('live hour nudge', V.Hour12, NextHour12(BeforeH));
    Expect('live AM/PM unchanged', V.IsPM, BeforePM);
    ExpectWord('live minute unchanged', V.Minute, BeforeMin);
    Expect('offset is in use', M.OffsetSeconds <> 0, True);
    M.ResetToSystem;
    Expect('reset clears offset', M.OffsetSeconds = 0, True);
    Expect('reset unfreezes', M.Frozen, False);
  finally
    M.Free;
  end;

  Path := IncludeTrailingPathDelimiter(GetTempDir) + 'classic-mac-alarm-test.ini';
  DeleteFile(Path);
  M := TAlarmModel.Create(Path);
  try
    M.SetAlarmTime(6, 30, 0, True);
    M.ToggleSwitch;
  finally
    M.Free;
  end;
  M := TAlarmModel.Create(Path);
  try
    V := M.Snapshot;
    ExpectWord('saved hour', V.AlarmH, 6);
    ExpectWord('saved minute', V.AlarmM, 30);
    Expect('saved PM', V.AlarmPM, True);
    Expect('saved switch comes back armed', M.Committed, True);
  finally
    M.Free;
  end;
  DeleteFile(Path);

  M := TAlarmModel.Create('');
  try
    V := M.Snapshot;
    Lay := BuildLayout(V);
    CX := (Lay.Lever.L + Lay.Lever.R) div 2;
    CY := (Lay.Lever.T + Lay.Lever.B) div 2;
    if HitTest(Lay, CX, CY) <> hitLever then
      Fail('lever hit');
    WriteLn('ok   lever hit');
    if HitTest(Lay, 1, 1) <> hitNone then
      Fail('corner should miss');
    WriteLn('ok   corner miss');
    CX := (Lay.Close.L + Lay.Close.R) div 2;
    CY := (Lay.Close.T + Lay.Close.B) div 2;
    if HitTest(Lay, CX, CY) <> hitClose then
      Fail('close mark hit');
    WriteLn('ok   close mark hit');
    if Lay.Lever.B > AlarmContentH(False) then
      Fail('lever hangs out of the compact window');
    WriteLn('ok   lever inside compact window');
    M.ToggleLever;
    V := M.Snapshot;
    Lay := BuildLayout(V);
    if AlarmContentH(True) <= AlarmContentH(False) then
      Fail('expanded should be taller');
    WriteLn('ok   expanded is taller');
    if (Lay.TimeButton.T <> Lay.DateButton.T) or (Lay.DateButton.T <> Lay.AlarmButton.T) then
      Fail('clock, calendar, and alarm should share one row');
    if (Lay.TimeButton.R > Lay.DateButton.L) or (Lay.DateButton.R > Lay.AlarmButton.L) then
      Fail('pictures should run clock, calendar, alarm');
    if Lay.DateMonth.B > Lay.TimeButton.T then
      Fail('the date line should sit above the pictures');
    if Lay.TimeButton.T < AlarmContentH(False) then
      Fail('pictures should sit in the open panel');
    WriteLn('ok   date line, then three pictures');
    M.SelectRow(rowAlarm);
    V := M.Snapshot;
    Lay := BuildLayout(V);
    CX := (Lay.Switch.L + Lay.Switch.R) div 2;
    CY := (Lay.Switch.T + Lay.Switch.B) div 2;
    if HitTest(Lay, CX, CY) <> hitSwitch then
      Fail('switch hit');
    WriteLn('ok   switch hit');
  finally
    M.Free;
  end;

  Buf := TPixelBuffer.Create(AlarmContentW, AlarmContentH(False));
  try
    M := TAlarmModel.Create('');
    try
      M.FreezeAt(2026, 10, 1, 9, 41, 5);
      RenderAlarm(Buf, M.Snapshot, 1);
      P := Buf.Ptr;
      Black := 0;
      N := Buf.Width * Buf.Height;
      for I := 0 to N - 1 do
      begin
        if P[0] < 16 then
          Inc(Black);
        Inc(P, 4);
      end;
      if Black < 80 then
        Fail('compact frame looks blank');
      WriteLn('ok   compact frame has ink (', Black, ')');
    finally
      M.Free;
    end;
  finally
    Buf.Free;
  end;

  WriteLn('All alarm tests passed.');
end.
