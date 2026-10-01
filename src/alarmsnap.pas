program alarmsnap;

{$mode objfpc}{$H+}

{ Writes PPM frames of the software canvas (no window).
  Usage: alarmsnap out-dir }

uses
  SysUtils, ualarmapp, ualarmmodel;

procedure WritePPM(const Path: string; C: TAlarmController);
var
  F: File;
  X, Y: Integer;
  P: PByte;
  RGB: array[0..2] of Byte;
  Header: string;
begin
  C.ApplyChrome;
  C.Render;
  Header := Format('P6'#10'%d %d'#10'255'#10, [C.Canvas.Width, C.Canvas.Height]);
  AssignFile(F, Path);
  Rewrite(F, 1);
  BlockWrite(F, Header[1], Length(Header));
  for Y := 0 to C.Canvas.Height - 1 do
  begin
    P := C.Canvas.Ptr + Y * C.Canvas.Width * 4;
    for X := 0 to C.Canvas.Width - 1 do
    begin
      RGB[0] := P[0];
      RGB[1] := P[1];
      RGB[2] := P[2];
      BlockWrite(F, RGB[0], 3);
      Inc(P, 4);
    end;
  end;
  CloseFile(F);
end;

function Wall(Y, M, D, H, Min, S: Word): TWall;
begin
  Result.Year := Y;
  Result.Month := M;
  Result.Day := D;
  Result.Hour24 := H;
  Result.Minute := Min;
  Result.Second := S;
end;

var
  Dir: string;
  C: TAlarmController;
begin
  if ParamCount >= 1 then
    Dir := ParamStr(1)
  else
    Dir := 'build';
  ForceDirectories(Dir);
  Dir := IncludeTrailingPathDelimiter(Dir);
  { Scale 2 matches a retina buffer and is large enough to read. }
  C := TAlarmController.Create(2, '');
  try
    C.Model.Pose(False, Wall(2026, 10, 1, 9, 41, 5),
      7, 0, 0, False, False, False, False, False,
      rowNone, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-compact.ppm', C);

    C.Model.Pose(True, Wall(2026, 10, 1, 15, 45, 12),
      7, 0, 0, True, True, True, False, False,
      rowNone, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-panel.ppm', C);

    C.Model.Pose(True, Wall(2026, 10, 1, 15, 45, 12),
      7, 30, 0, True, True, False, False, False,
      rowAlarm, partMonth, partHour, partHour);
    C.Model.SelectAlarmPart(partHour);
    WritePPM(Dir + 'snap-editing.ppm', C);

    C.Model.Pose(True, Wall(2026, 10, 1, 20, 4, 13),
      12, 0, 0, False, False, False, False, False,
      rowTime, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-clock.ppm', C);

    C.Model.Pose(True, Wall(2026, 10, 1, 20, 4, 57),
      12, 0, 0, False, False, False, False, False,
      rowDate, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-date.ppm', C);

    C.Model.Pose(False, Wall(2026, 10, 1, 7, 0, 0),
      7, 0, 0, False, True, True, True, True,
      rowNone, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-ringing.ppm', C);

    C.Model.Pose(False, Wall(2026, 10, 1, 7, 0, 0),
      7, 0, 0, False, True, True, True, False,
      rowNone, partMonth, partHour, partHour);
    WritePPM(Dir + 'snap-ring-quiet.ppm', C);
  finally
    C.Free;
  end;
end.
