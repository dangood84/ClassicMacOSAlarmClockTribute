unit ualarmrender;

{$mode objfpc}{$H+}

{ Software RGBA canvas for the Alarm Clock desk accessory.

  The face is the window. Hosts draw it borderless: no system title bar.
  A hairline is the panel's own edge. A small close mark quits. Empty
  pixels drag it.

  Compact is the time and the key. Open, one line shows whichever
  picture is lit, and under it three pictures: a clock, a calendar,
  and an alarm. Opening the key lights the calendar. The date on the
  line is month/day/year, two digits of the year. The calendar picture
  is a 2 on the back sheet and a bold 1 on the front, not the live day.
  The knob sits to the left of the alarm time. The crosshair belongs
  on the line under the time.

  On a Mac the time and the date are bold Geneva, centered. Geneva has
  no bold face, so ualarmtext draws it twice, one pixel apart. The 5×7
  glyphs remain for hosts that do not have that font. They are not
  Chicago, and not a copy of the desk accessory's bitmaps. Date slashes
  on that face are a stroke in the reserved gap, not a glyph lookup.

  Hosts only upload the buffer. Logical pixels are multiplied by
  PixelScale so a retina Mac stays crisp and a 1× Catalina or Pi display
  stays 1:1. }

interface

uses
  ualarmmodel;

type
  TPixelBuffer = class
  private
    FWidth, FHeight: Integer;
    FData: array of Byte;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear(R, G, B, A: Byte);
    function Ptr: PByte;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

  THitKind = (
    hitNone,
    hitClose,
    hitLever,
    hitDateIcon, hitTimeIcon, hitAlarmIcon,
    hitSwitch,
    hitArrowUp, hitArrowDown,
    hitDateMonth, hitDateDay, hitDateYear,
    hitTimeHour, hitTimeMinute, hitTimeSecond, hitTimeAmPm,
    hitAlarmHour, hitAlarmMinute, hitAlarmSecond, hitAlarmAmPm
  );

  TRectI = record
    L, T, R, B: Integer;
  end;

  TAlarmLayout = record
    Close, Lever, Switch: TRectI;
    DateButton, TimeButton, AlarmButton: TRectI;
    DateIcon, TimeIcon, AlarmIcon: TRectI;
    ArrowUp, ArrowDown: TRectI;
    DateMonth, DateDay, DateYear: TRectI;
    TimeHour, TimeMinute, TimeSecond, TimeAmPm: TRectI;
    AlarmHour, AlarmMinute, AlarmSecond, AlarmAmPm: TRectI;
    AlarmRowTop: Integer;
    RowHeight: Integer;
    ArrowsVisible: Boolean;
    Active: THitKind;
  end;

const
  AlarmContentW = 128;

function AlarmContentH(Expanded: Boolean): Integer;
function BuildLayout(const V: TAlarmView): TAlarmLayout;
function HitTest(const Lay: TAlarmLayout; X, Y: Integer): THitKind;
procedure RenderAlarm(Buf: TPixelBuffer; const V: TAlarmView; PixelScale: Integer);
procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);
{ Ink in the pixel-face date slash. Zero means the mark is missing or
  slopes the wrong way. The Pi draws this stroke; the Mac uses Geneva. }
function PixelDateSlashInk: Integer;

implementation

uses
  SysUtils, ualarmtext;

const
  TimeBandTop = 2;
  TimeBandH = 16;
  CompactH = 20;
  ValueH = 20;
  IconH = 32;
  { The line under the time, then the three picture buttons. }
  ExpandedExtra = ValueH + IconH; { 52 }
  BigPt = 12;
  PanelPt = 12;
  SetPt = 9;
  DateH = ValueH;
  BoxH = IconH;
  { Fallback sizes for the 5×7 face, on a host with no Geneva. }
  BigScale = 2;
  PanelScale = 2;
  IconSize = 15;
  CloseSize = 11;
  RowH = BoxH;

function AlarmContentH(Expanded: Boolean): Integer;
begin
  Result := CompactH;
  if Expanded then
    Inc(Result, ExpandedExtra);
end;

function EmptyRect: TRectI;
begin
  Result.L := 0;
  Result.T := 0;
  Result.R := 0;
  Result.B := 0;
end;

function MakeRect(L, T, R, B: Integer): TRectI;
begin
  Result.L := L;
  Result.T := T;
  Result.R := R;
  Result.B := B;
end;

function PointIn(const R: TRectI; X, Y: Integer): Boolean;
begin
  Result := (X >= R.L) and (X < R.R) and (Y >= R.T) and (Y < R.B);
end;

function ActiveHit(const V: TAlarmView): THitKind;
begin
  Result := hitNone;
  case V.Row of
    rowDate:
      case V.DatePart of
        partMonth: Result := hitDateMonth;
        partDay: Result := hitDateDay;
        partYear: Result := hitDateYear;
      end;
    rowTime:
      case V.TimePart of
        partHour: Result := hitTimeHour;
        partMinute: Result := hitTimeMinute;
        partSecond: Result := hitTimeSecond;
        partAmPm: Result := hitTimeAmPm;
      end;
    rowAlarm:
      case V.AlarmPart of
        partHour: Result := hitAlarmHour;
        partMinute: Result := hitAlarmMinute;
        partSecond: Result := hitAlarmSecond;
        partAmPm: Result := hitAlarmAmPm;
      end;
  end;
end;

function AmPmText(PM: Boolean): string;
begin
  if PM then
    Result := 'PM'
  else
    Result := 'AM';
end;

function TwoDigits(N: Word): string;
begin
  Result := Char(Ord('0') + (N div 10) mod 10) + Char(Ord('0') + (N mod 10));
end;

function Shown(const V: TAlarmView; Hit: THitKind; const Normal: string): string;
begin
  { While a multi-key entry is in progress, draw those digits, not the
    value they will become. Year entry uses this so "20" does not paint
    as the year 20. }
  if (V.Typing <> '') and (Hit = ActiveHit(V)) then
    Result := V.Typing
  else
    Result := Normal;
end;

type
  TGlyph = array[0..6] of Byte;

const
  GlyphChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:, /';
  { Seven rows, five columns, '1' is ink. Original face, not Chicago. }
  FontSrc: array[0..39] of string = (
    '01110'+'10001'+'10001'+'10001'+'10001'+'10001'+'01110', { 0 }
    '00100'+'01100'+'00100'+'00100'+'00100'+'00100'+'01110', { 1 }
    '01110'+'10001'+'00001'+'00010'+'00100'+'01000'+'11111', { 2 }
    '01110'+'10001'+'00001'+'00110'+'00001'+'10001'+'01110', { 3 }
    '00010'+'00110'+'01010'+'10010'+'11111'+'00010'+'00010', { 4 }
    '11111'+'10000'+'11110'+'00001'+'00001'+'10001'+'01110', { 5 }
    '00110'+'01000'+'10000'+'11110'+'10001'+'10001'+'01110', { 6 }
    '11111'+'00001'+'00010'+'00100'+'01000'+'01000'+'01000', { 7 }
    '01110'+'10001'+'10001'+'01110'+'10001'+'10001'+'01110', { 8 }
    '01110'+'10001'+'10001'+'01111'+'00001'+'00010'+'01100', { 9 }
    '01110'+'10001'+'10001'+'11111'+'10001'+'10001'+'10001', { A }
    '11110'+'10001'+'10001'+'11110'+'10001'+'10001'+'11110', { B }
    '01111'+'10000'+'10000'+'10000'+'10000'+'10000'+'01111', { C }
    '11110'+'10001'+'10001'+'10001'+'10001'+'10001'+'11110', { D }
    '11111'+'10000'+'10000'+'11110'+'10000'+'10000'+'11111', { E }
    '11111'+'10000'+'10000'+'11110'+'10000'+'10000'+'10000', { F }
    '01110'+'10001'+'10000'+'10111'+'10001'+'10001'+'01110', { G }
    '10001'+'10001'+'10001'+'11111'+'10001'+'10001'+'10001', { H }
    '01110'+'00100'+'00100'+'00100'+'00100'+'00100'+'01110', { I }
    '00001'+'00001'+'00001'+'00001'+'10001'+'10001'+'01110', { J }
    '10001'+'10010'+'10100'+'11000'+'10100'+'10010'+'10001', { K }
    '10000'+'10000'+'10000'+'10000'+'10000'+'10000'+'11111', { L }
    '10001'+'11011'+'10101'+'10001'+'10001'+'10001'+'10001', { M }
    '10001'+'11001'+'10101'+'10011'+'10001'+'10001'+'10001', { N }
    '01110'+'10001'+'10001'+'10001'+'10001'+'10001'+'01110', { O }
    '11110'+'10001'+'10001'+'11110'+'10000'+'10000'+'10000', { P }
    '01110'+'10001'+'10001'+'10001'+'10101'+'10010'+'01101', { Q }
    '11110'+'10001'+'10001'+'11110'+'10100'+'10010'+'10001', { R }
    '01111'+'10000'+'10000'+'01110'+'00001'+'00001'+'11110', { S }
    '11111'+'00100'+'00100'+'00100'+'00100'+'00100'+'00100', { T }
    '10001'+'10001'+'10001'+'10001'+'10001'+'10001'+'01110', { U }
    '10001'+'10001'+'10001'+'10001'+'10001'+'01010'+'00100', { V }
    '10001'+'10001'+'10001'+'10101'+'10101'+'11011'+'10001', { W }
    '10001'+'10001'+'01010'+'00100'+'01010'+'10001'+'10001', { X }
    '10001'+'10001'+'01010'+'00100'+'00100'+'00100'+'00100', { Y }
    '11111'+'00001'+'00010'+'00100'+'01000'+'10000'+'11111', { Z }
    '00000'+'00100'+'00100'+'00000'+'00100'+'00100'+'00000', { : }
    '00000'+'00000'+'00000'+'00110'+'00100'+'01000'+'00000', { , }
    '00000'+'00000'+'00000'+'00000'+'00000'+'00000'+'00000', { space }
    '00001'+'00010'+'00010'+'00100'+'00100'+'01000'+'10000'  { / }
  );

var
  GlyphCache: array[0..39] of TGlyph;
  GlyphReady: Boolean;

function DecodeGlyph(const S: string): TGlyph;
var
  Row, Col, Bit, Index: Integer;
begin
  for Row := 0 to 6 do
  begin
    Bit := 0;
    for Col := 0 to 4 do
    begin
      Index := Row * 5 + Col + 1;
      if (Index <= Length(S)) and (S[Index] = '1') then
        Bit := Bit or (1 shl (4 - Col));
    end;
    Result[Row] := Bit;
  end;
end;

procedure EnsureFont;
var
  I: Integer;
begin
  if GlyphReady then
    Exit;
  for I := 0 to High(FontSrc) do
    GlyphCache[I] := DecodeGlyph(FontSrc[I]);
  GlyphReady := True;
end;

function GlyphIndex(Ch: Char): Integer;
var
  I: Integer;
begin
  Ch := UpCase(Ch);
  for I := 1 to Length(GlyphChars) do
    if GlyphChars[I] = Ch then
      Exit(I - 1);
  Result := -1;
end;

function FaceWidth(const S: string; Pt: Integer): Integer;
begin
  Result := AlarmTextWidth(S, Pt, True);
end;

function Year2(Y: Word): string;
begin
  Result := TwoDigits(Y mod 100);
end;

function HourPlain(H: Word): string;
begin
  if H = 0 then
    H := 12;
  if H > 12 then
    H := 12;
  Result := IntToStr(H);
end;

function DateLineWidth(const V: TAlarmView): Integer;
begin
  Result := FaceWidth(Shown(V, hitDateMonth, IntToStr(V.Month)), PanelPt)
    + FaceWidth('/ ', PanelPt)
    + FaceWidth(Shown(V, hitDateDay, IntToStr(V.Day)), PanelPt)
    + FaceWidth('/', PanelPt)
    + FaceWidth(Shown(V, hitDateYear, Year2(V.Year)), PanelPt);
end;

function ClockLineWidth(const V: TAlarmView; Alarm: Boolean): Integer;
begin
  if Alarm then
    Result := FaceWidth(Shown(V, hitAlarmHour, HourPlain(V.AlarmH)), PanelPt)
  else
    Result := FaceWidth(Shown(V, hitTimeHour, HourPlain(V.Hour12)), PanelPt);
  Result := Result + FaceWidth(':', PanelPt);
  if Alarm then
    Result := Result + FaceWidth(Shown(V, hitAlarmMinute, TwoDigits(V.AlarmM)), PanelPt)
  else
    Result := Result + FaceWidth(Shown(V, hitTimeMinute, TwoDigits(V.Minute)), PanelPt);
  Result := Result + FaceWidth(':', PanelPt);
  if Alarm then
    Result := Result + FaceWidth(Shown(V, hitAlarmSecond, TwoDigits(V.AlarmS)), PanelPt)
      + FaceWidth(' ', PanelPt)
      + FaceWidth(Shown(V, hitAlarmAmPm, AmPmText(V.AlarmPM)), PanelPt)
  else
    Result := Result + FaceWidth(Shown(V, hitTimeSecond, TwoDigits(V.Second)), PanelPt)
      + FaceWidth(' ', PanelPt)
      + FaceWidth(Shown(V, hitTimeAmPm, AmPmText(V.IsPM)), PanelPt);
end;

procedure AddSpan(var X: Integer; const Text: string; Pt, RowTop, RowHeight: Integer;
  out R: TRectI);
var
  W: Integer;
begin
  W := FaceWidth(Text, Pt);
  R := MakeRect(X, RowTop, X + W, RowTop + RowHeight);
  Inc(X, W);
end;

function CenteredIcon(const Btn: TRectI): TRectI;
var
  X, Y: Integer;
begin
  X := Btn.L + ((Btn.R - Btn.L) - IconSize) div 2;
  Y := Btn.T + ((Btn.B - Btn.T) - IconSize) div 2;
  Result := MakeRect(X, Y, X + IconSize, Y + IconSize);
end;

procedure AddTimeSpans(var X: Integer; const V: TAlarmView; RowTop, RowHeight: Integer;
  Alarm: Boolean; var Lay: TAlarmLayout);
var
  Dummy: TRectI;
begin
  if Alarm then
  begin
    AddSpan(X, Shown(V, hitAlarmHour, HourPlain(V.AlarmH)), PanelPt, RowTop, RowHeight, Lay.AlarmHour);
    AddSpan(X, ':', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitAlarmMinute, TwoDigits(V.AlarmM)), PanelPt, RowTop, RowHeight, Lay.AlarmMinute);
    AddSpan(X, ':', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitAlarmSecond, TwoDigits(V.AlarmS)), PanelPt, RowTop, RowHeight, Lay.AlarmSecond);
    AddSpan(X, ' ', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitAlarmAmPm, AmPmText(V.AlarmPM)), PanelPt, RowTop, RowHeight, Lay.AlarmAmPm);
  end
  else
  begin
    AddSpan(X, Shown(V, hitTimeHour, HourPlain(V.Hour12)), PanelPt, RowTop, RowHeight, Lay.TimeHour);
    AddSpan(X, ':', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitTimeMinute, TwoDigits(V.Minute)), PanelPt, RowTop, RowHeight, Lay.TimeMinute);
    AddSpan(X, ':', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitTimeSecond, TwoDigits(V.Second)), PanelPt, RowTop, RowHeight, Lay.TimeSecond);
    AddSpan(X, ' ', PanelPt, RowTop, RowHeight, Dummy);
    AddSpan(X, Shown(V, hitTimeAmPm, AmPmText(V.IsPM)), PanelPt, RowTop, RowHeight, Lay.TimeAmPm);
  end;
end;

function BuildLayout(const V: TAlarmView): TAlarmLayout;
var
  X, ValueTop, BoxTop, BoxW, ArrowX: Integer;
  Dummy: TRectI;
  Show: TRowKind;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RowHeight := ValueH;
  if V.Editing then
    Result.Active := ActiveHit(V)
  else
    Result.Active := hitNone;
  Result.ArrowsVisible := V.Expanded and V.Editing;

  { Empty close square, inset the way the contracted face shows it. }
  Result.Close := MakeRect(10, 5, 10 + CloseSize, 5 + CloseSize);
  { The key stays at the right of the time strip, contracted or open. }
  X := AlarmContentW - 20;
  Result.Lever := MakeRect(X, 2, X + 14, 17);

  if not V.Expanded then
    Exit;

  { Opening the lever reveals a line, then three equal pictures:
    clock, calendar, alarm. The line shows whichever picture is lit. }
  ValueTop := CompactH;
  BoxTop := CompactH + ValueH;
  BoxW := (AlarmContentW - 2) div 3;
  Result.AlarmRowTop := ValueTop;
  Result.TimeButton := MakeRect(1, BoxTop, 1 + BoxW, BoxTop + IconH);
  Result.DateButton := MakeRect(1 + BoxW, BoxTop, 1 + 2 * BoxW, BoxTop + IconH);
  Result.AlarmButton := MakeRect(1 + 2 * BoxW, BoxTop, AlarmContentW - 1, BoxTop + IconH);
  Result.TimeIcon := CenteredIcon(Result.TimeButton);
  Result.DateIcon := CenteredIcon(Result.DateButton);
  Result.AlarmIcon := CenteredIcon(Result.AlarmButton);

  Show := V.Row;
  if Show = rowNone then
    Show := rowDate;

  { Centre the line. The alarm switch sits just left of its time. }
  if Result.ArrowsVisible then
    ArrowX := AlarmContentW - 16
  else
    ArrowX := AlarmContentW - 4;
  if Show = rowAlarm then
    X := ClockLineWidth(V, True) + 13
  else if Show = rowDate then
    X := DateLineWidth(V)
  else
    X := ClockLineWidth(V, False);
  X := 4 + (ArrowX - 4 - X) div 2;
  if X < 4 then
    X := 4;
  if Show = rowAlarm then
  begin
    Result.Switch := MakeRect(X, ValueTop + 2, X + 10, ValueTop + ValueH - 2);
    X := Result.Switch.R + 3;
  end;

  if Show = rowDate then
  begin
    { "10/ 1/26", the spacing on the classic face. }
    AddSpan(X, Shown(V, hitDateMonth, IntToStr(V.Month)), PanelPt, ValueTop, ValueH, Result.DateMonth);
    AddSpan(X, '/ ', PanelPt, ValueTop, ValueH, Dummy);
    AddSpan(X, Shown(V, hitDateDay, IntToStr(V.Day)), PanelPt, ValueTop, ValueH, Result.DateDay);
    AddSpan(X, '/', PanelPt, ValueTop, ValueH, Dummy);
    AddSpan(X, Shown(V, hitDateYear, Year2(V.Year)), PanelPt, ValueTop, ValueH, Result.DateYear);
  end
  else if Show = rowTime then
    AddTimeSpans(X, V, ValueTop, ValueH, False, Result)
  else
    AddTimeSpans(X, V, ValueTop, ValueH, True, Result);

  if Result.ArrowsVisible then
  begin
    ArrowX := AlarmContentW - 14;
    Result.ArrowUp := MakeRect(ArrowX, ValueTop, ArrowX + 12, ValueTop + ValueH div 2);
    Result.ArrowDown := MakeRect(ArrowX, ValueTop + ValueH div 2, ArrowX + 12, ValueTop + ValueH);
  end;
end;

function HitTest(const Lay: TAlarmLayout; X, Y: Integer): THitKind;
begin
  if Lay.ArrowsVisible and PointIn(Lay.ArrowUp, X, Y) then
    Exit(hitArrowUp);
  if Lay.ArrowsVisible and PointIn(Lay.ArrowDown, X, Y) then
    Exit(hitArrowDown);
  if PointIn(Lay.Lever, X, Y) then
    Exit(hitLever);
  if PointIn(Lay.Close, X, Y) then
    Exit(hitClose);
  if PointIn(Lay.Switch, X, Y) then
    Exit(hitSwitch);
  if PointIn(Lay.DateButton, X, Y) then
    Exit(hitDateIcon);
  if PointIn(Lay.TimeButton, X, Y) then
    Exit(hitTimeIcon);
  if PointIn(Lay.AlarmButton, X, Y) then
    Exit(hitAlarmIcon);
  if PointIn(Lay.DateMonth, X, Y) then
    Exit(hitDateMonth);
  if PointIn(Lay.DateDay, X, Y) then
    Exit(hitDateDay);
  if PointIn(Lay.DateYear, X, Y) then
    Exit(hitDateYear);
  if PointIn(Lay.TimeHour, X, Y) then
    Exit(hitTimeHour);
  if PointIn(Lay.TimeMinute, X, Y) then
    Exit(hitTimeMinute);
  if PointIn(Lay.TimeSecond, X, Y) then
    Exit(hitTimeSecond);
  if PointIn(Lay.TimeAmPm, X, Y) then
    Exit(hitTimeAmPm);
  if PointIn(Lay.AlarmHour, X, Y) then
    Exit(hitAlarmHour);
  if PointIn(Lay.AlarmMinute, X, Y) then
    Exit(hitAlarmMinute);
  if PointIn(Lay.AlarmSecond, X, Y) then
    Exit(hitAlarmSecond);
  if PointIn(Lay.AlarmAmPm, X, Y) then
    Exit(hitAlarmAmPm);
  Result := hitNone;
end;

constructor TPixelBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

procedure TPixelBuffer.Resize(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then
    AWidth := 1;
  if AHeight < 1 then
    AHeight := 1;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FData, FWidth * FHeight * 4);
end;

procedure TPixelBuffer.Clear(R, G, B, A: Byte);
var
  I: Integer;
  P: PByte;
begin
  if Length(FData) = 0 then
    Exit;
  P := @FData[0];
  I := 0;
  while I < Length(FData) do
  begin
    P[I] := R;
    P[I + 1] := G;
    P[I + 2] := B;
    P[I + 3] := A;
    Inc(I, 4);
  end;
end;

function TPixelBuffer.Ptr: PByte;
begin
  if Length(FData) = 0 then
    Result := nil
  else
    Result := @FData[0];
end;

procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);
var
  I, N: Integer;
  S, D: PByte;
begin
  S := Buf.Ptr;
  D := Dest;
  N := Buf.Width * Buf.Height;
  for I := 0 to N - 1 do
  begin
    D[0] := S[2];
    D[1] := S[1];
    D[2] := S[0];
    D[3] := S[3];
    Inc(S, 4);
    Inc(D, 4);
  end;
end;

{ The painter speaks in logical pixels. Each one becomes PixelScale
  device pixels so the font stays on the pixel grid. }

type
  TPainter = class
  public
    Buf: TPixelBuffer;
    Scale: Integer;
    procedure Fill(X, Y, W, H: Integer; R, G, B: Byte);
    procedure Stroke(X, Y, W, H, Thick: Integer; R, G, B: Byte);
    procedure Glyph(X, Y: Integer; Ch: Char; FontScale: Integer; Ink: Byte);
    function Text(X, Y: Integer; const S: string; FontScale: Integer; Ink: Byte): Integer;
    procedure TriUp(X, Y, W, H: Integer; Ink: Byte);
    procedure TriDown(X, Y, W, H: Integer; Ink: Byte);
    procedure Disc(CX, CY, Radius: Integer; Ink: Byte);
    procedure Ring(CX, CY, Radius: Integer; Ink: Byte);
  end;

procedure TPainter.Fill(X, Y, W, H: Integer; R, G, B: Byte);
var
  PX, PY, X0, Y0, X1, Y1, Row: Integer;
  P: PByte;
begin
  if (Scale < 1) or (W <= 0) or (H <= 0) or (Buf = nil) or (Buf.Ptr = nil) then
    Exit;
  X0 := X * Scale;
  Y0 := Y * Scale;
  X1 := (X + W) * Scale;
  Y1 := (Y + H) * Scale;
  if X0 < 0 then
    X0 := 0;
  if Y0 < 0 then
    Y0 := 0;
  if X1 > Buf.Width then
    X1 := Buf.Width;
  if Y1 > Buf.Height then
    Y1 := Buf.Height;
  for PY := Y0 to Y1 - 1 do
  begin
    Row := PY * Buf.Width;
    P := Buf.Ptr + (Row + X0) * 4;
    for PX := X0 to X1 - 1 do
    begin
      P[0] := R;
      P[1] := G;
      P[2] := B;
      P[3] := 255;
      Inc(P, 4);
    end;
  end;
end;

procedure TPainter.Stroke(X, Y, W, H, Thick: Integer; R, G, B: Byte);
var
  I: Integer;
begin
  if Thick < 1 then
    Thick := 1;
  for I := 0 to Thick - 1 do
  begin
    Fill(X + I, Y + I, W - I * 2, 1, R, G, B);
    Fill(X + I, Y + H - 1 - I, W - I * 2, 1, R, G, B);
    Fill(X + I, Y + I, 1, H - I * 2, R, G, B);
    Fill(X + W - 1 - I, Y + I, 1, H - I * 2, R, G, B);
  end;
end;

procedure TPainter.Glyph(X, Y: Integer; Ch: Char; FontScale: Integer; Ink: Byte);
var
  Index, Row, Col: Integer;
  G: TGlyph;
begin
  EnsureFont;
  Index := GlyphIndex(Ch);
  if Index < 0 then
    Exit;
  G := GlyphCache[Index];
  for Row := 0 to 6 do
    for Col := 0 to 4 do
      if (G[Row] and (1 shl (4 - Col))) <> 0 then
        Fill(X + Col * FontScale, Y + Row * FontScale, FontScale, FontScale, Ink, Ink, Ink);
end;

function TPainter.Text(X, Y: Integer; const S: string; FontScale: Integer; Ink: Byte): Integer;
var
  I, Pen: Integer;
begin
  Pen := X;
  for I := 1 to Length(S) do
  begin
    Glyph(Pen, Y, S[I], FontScale, Ink);
    Inc(Pen, 5 * FontScale + FontScale);
  end;
  Result := Pen - X;
  if S = '' then
    Result := 0
  else
    Dec(Result, FontScale); { the loop adds a trailing gap }
end;

procedure TPainter.TriUp(X, Y, W, H: Integer; Ink: Byte);
var
  Row, Half, CX: Integer;
begin
  if H < 1 then
    Exit;
  CX := X + W div 2;
  for Row := 0 to H - 1 do
  begin
    Half := (W * (Row + 1)) div (2 * H);
    if Half < 1 then
      Half := 1;
    Fill(CX - Half, Y + Row, Half * 2, 1, Ink, Ink, Ink);
  end;
end;

procedure TPainter.TriDown(X, Y, W, H: Integer; Ink: Byte);
var
  Row, Half, CX: Integer;
begin
  if H < 1 then
    Exit;
  CX := X + W div 2;
  for Row := 0 to H - 1 do
  begin
    Half := (W * (H - Row)) div (2 * H);
    if Half < 1 then
      Half := 1;
    Fill(CX - Half, Y + Row, Half * 2, 1, Ink, Ink, Ink);
  end;
end;

procedure TPainter.Disc(CX, CY, Radius: Integer; Ink: Byte);
var
  X, Y, R2: Integer;
begin
  R2 := Radius * Radius;
  for Y := -Radius to Radius do
    for X := -Radius to Radius do
      if X * X + Y * Y <= R2 then
        Fill(CX + X, CY + Y, 1, 1, Ink, Ink, Ink);
end;

procedure TPainter.Ring(CX, CY, Radius: Integer; Ink: Byte);
var
  X, Y, D: Integer;
begin
  for Y := -Radius to Radius do
    for X := -Radius to Radius do
    begin
      D := X * X + Y * Y;
      if (D <= Radius * Radius) and (D >= (Radius - 1) * (Radius - 1)) then
        Fill(CX + X, CY + Y, 1, 1, Ink, Ink, Ink);
    end;
end;

procedure BlitMask(P: TPainter; X, Y: Integer; const Rows: array of string; Ink: Byte);
var
  Row, Col: Integer;
  Line: string;
begin
  for Row := 0 to High(Rows) do
  begin
    Line := Rows[Row];
    for Col := 1 to Length(Line) do
      if Line[Col] = '#' then
        P.Fill(X + Col - 1, Y + Row, 1, 1, Ink, Ink, Ink);
  end;
end;

procedure DrawLever(P: TPainter; const R: TRectI; PointingDown: Boolean);
const
  { One key. Open: bow on top, tooth at the bottom. Shut is that
    picture turned 180 degrees, so the tooth points up. }
  KeyOpen: array[0..8] of string = (
    '.###.',
    '#####',
    '##.##',
    '#####',
    '.###.',
    '.#...',
    '.#...',
    '.###.',
    '.###.'
  );
  KeyShut: array[0..8] of string = (
    '.###.',
    '.###.',
    '...#.',
    '...#.',
    '.###.',
    '#####',
    '##.##',
    '#####',
    '.###.'
  );
var
  X, Y: Integer;
begin
  X := R.L + ((R.R - R.L) - 5) div 2;
  Y := R.T + ((R.B - R.T) - 9) div 2;
  if PointingDown then
    BlitMask(P, X, Y, KeyOpen, 0)
  else
    BlitMask(P, X, Y, KeyShut, 0);
end;

procedure DrawChoice(P: TPainter; const R: TRectI; Selected: Boolean);
var
  W, H: Integer;
begin
  W := R.R - R.L;
  H := R.B - R.T;
  if Selected then
    P.Fill(R.L, R.T, W, H, 0, 0, 0)
  else
    P.Stroke(R.L, R.T, W, H, 1, 0, 0, 0);
end;

procedure DrawClose(P: TPainter; const R: TRectI);
begin
  { Empty square, the way the close mark looks on the classic face. }
  P.Stroke(R.L, R.T, R.R - R.L, R.B - R.T, 1, 0, 0, 0);
end;

procedure DrawFace(Buf: TPixelBuffer; P: TPainter; X, Y: Integer; const S: string;
  Pt: Integer; White, Bold: Boolean); forward;

procedure HairCircle(P: TPainter; CX, CY, R: Integer; Ink: Byte; TopOnly: Boolean);
var
  X, Y, Err: Integer;
  procedure Plot(PX, PY: Integer);
  begin
    if TopOnly and (PY > CY) then
      Exit;
    P.Fill(PX, PY, 1, 1, Ink, Ink, Ink);
  end;
begin
  if R < 1 then
    Exit;
  X := 0;
  Y := R;
  Err := 3 - 2 * R;
  while X <= Y do
  begin
    Plot(CX + X, CY + Y);
    Plot(CX - X, CY + Y);
    Plot(CX + X, CY - Y);
    Plot(CX - X, CY - Y);
    Plot(CX + Y, CY + X);
    Plot(CX - Y, CY + X);
    Plot(CX + Y, CY - X);
    Plot(CX - Y, CY - X);
    if Err < 0 then
      Err := Err + 4 * X + 6
    else
    begin
      Err := Err + 4 * (X - Y) + 10;
      Dec(Y);
    end;
    Inc(X);
  end;
end;

procedure Hands(P: TPainter; CX, CY, UpLen, MinuteLen: Integer; Ink: Byte);
var
  I: Integer;
begin
  { Hour toward twelve. The minute hand points toward five and stops short. }
  P.Fill(CX, CY - UpLen, 1, UpLen + 1, Ink, Ink, Ink);
  for I := 1 to MinuteLen do
    P.Fill(CX + I, CY + I, 1, 1, Ink, Ink, Ink);
end;

procedure DrawClockIcon(P: TPainter; const Btn: TRectI; Ink: Byte);
var
  CX, CY: Integer;
begin
  CX := (Btn.L + Btn.R) div 2;
  CY := Btn.T + (Btn.B - Btn.T) div 2;
  HairCircle(P, CX, CY, 11, Ink, False);
  Hands(P, CX, CY, 8, 4, Ink);
end;

procedure DrawCalendarBtn(P: TPainter; const Btn: TRectI; Selected: Boolean);
const
  { 2 lives on the sheet behind. The front sheet carries a bold 1. }
  TwoDigit: array[0..9] of string = (
    '.######.',
    '#......#',
    '.......#',
    '......#.',
    '.....#..',
    '....#...',
    '...#....',
    '..#.....',
    '.#......',
    '########'
  );
  OneDigit: array[0..11] of string = (
    '..##..',
    '.###..',
    '####..',
    '..##..',
    '..##..',
    '..##..',
    '..##..',
    '..##..',
    '..##..',
    '..##..',
    '..##..',
    '.####.'
  );
var
  Ink, Paper: Byte;
  X, Y: Integer;
begin
  if Selected then
  begin
    Ink := 255;
    Paper := 0;
  end
  else
  begin
    Ink := 0;
    Paper := 255;
  end;
  X := Btn.L + ((Btn.R - Btn.L) - 23) div 2;
  Y := Btn.T + ((Btn.B - Btn.T) - 18) div 2;
  P.Stroke(X, Y, 16, 15, 1, Ink, Ink, Ink);
  P.Fill(X + 1, Y + 3, 14, 1, Ink, Ink, Ink);
  BlitMask(P, X + 2, Y + 4, TwoDigit, Ink);
  P.Fill(X + 8, Y + 3, 14, 14, Paper, Paper, Paper);
  P.Stroke(X + 8, Y + 3, 15, 15, 1, Ink, Ink, Ink);
  BlitMask(P, X + 12, Y + 5, OneDigit, Ink);
end;

procedure DrawAlarmIcon(P: TPainter; const Btn: TRectI; Ink: Byte);
var
  CX, CY, Rad, I: Integer;
begin
  CX := (Btn.L + Btn.R) div 2;
  CY := Btn.T + (Btn.B - Btn.T) div 2 + 1;
  Rad := 8;
  HairCircle(P, CX, CY - Rad - 1, 3, Ink, True);
  P.Fill(CX - 3, CY - Rad - 1, 7, 1, Ink, Ink, Ink);
  HairCircle(P, CX, CY, Rad, Ink, False);
  Hands(P, CX, CY, 5, 3, Ink);
  { Stands leave the lower corners and run down-out at 45 degrees. }
  for I := 0 to 3 do
  begin
    P.Fill(CX - 5 - I, CY + Rad - 1 + I, 1, 1, Ink, Ink, Ink);
    P.Fill(CX + 5 + I, CY + Rad - 1 + I, 1, 1, Ink, Ink, Ink);
  end;
end;

procedure DrawSwitch(P: TPainter; const R: TRectI; Up: Boolean; Ink: Byte);
const
  { Pill, knob in the lower half. Up is this picture turned over. }
  KnobDown: array[0..12] of string = (
    '..####..',
    '.#....#.',
    '#......#',
    '#......#',
    '#......#',
    '#..##..#',
    '#..##..#',
    '#.####.#',
    '#.####.#',
    '#......#',
    '#......#',
    '.#....#.',
    '..####..'
  );
var
  X, Y, Row, Col: Integer;
  Line: string;
begin
  if R.R <= R.L then
    Exit;
  X := R.L + ((R.R - R.L) - 8) div 2;
  Y := R.T + ((R.B - R.T) - 13) div 2;
  for Row := 0 to 12 do
  begin
    if Up then
      Line := KnobDown[12 - Row]
    else
      Line := KnobDown[Row];
    for Col := 1 to Length(Line) do
      if Line[Col] = '#' then
        P.Fill(X + Col - 1, Y + Row, 1, 1, Ink, Ink, Ink);
  end;
end;

procedure DrawArrows(P: TPainter; const UpR, DownR: TRectI);
var
  W, UH, DH: Integer;
begin
  W := UpR.R - UpR.L - 2;
  UH := UpR.B - UpR.T - 2;
  DH := DownR.B - DownR.T - 2;
  if W < 4 then
    W := 4;
  if UH < 3 then
    UH := 3;
  if DH < 3 then
    DH := 3;
  P.TriUp(UpR.L + 1, UpR.T + 1, W, UH, 0);
  P.TriDown(DownR.L + 1, DownR.T + 1, W, DH, 0);
end;

procedure DrawFace(Buf: TPixelBuffer; P: TPainter; X, Y: Integer; const S: string;
  Pt: Integer; White, Bold: Boolean);
{$IFNDEF DARWIN}
var
  Scale, Ink: Integer;
{$ENDIF}
begin
  {$IFDEF DARWIN}
  AlarmDrawText(Buf, X, Y, P.Scale, S, Pt, White, Bold);
  {$ELSE}
  if White then
    Ink := 255
  else
    Ink := 0;
  Scale := Pt div 7;
  if Scale < 1 then
    Scale := 1;
  P.Text(X, Y, S, Scale, Ink);
  if Bold then
    P.Text(X + Scale, Y, S, Scale, Ink);
  {$ENDIF}
end;

procedure DrawPixelSlash(P: TPainter; X, Y, FontScale: Integer);
const
  { Two pixels thick, same box as a 5×7 glyph. Top at the right. }
  Mark: array[0..6] of string = (
    '...##',
    '...##',
    '..##.',
    '..##.',
    '.##..',
    '.##..',
    '##...'
  );
var
  Row, Col, DX, DY: Integer;
  Line: string;
begin
  if FontScale < 1 then
    FontScale := 1;
  for Row := 0 to High(Mark) do
  begin
    Line := Mark[Row];
    for Col := 1 to Length(Line) do
      if Line[Col] = '#' then
        for DY := 0 to FontScale - 1 do
          for DX := 0 to FontScale - 1 do
            P.Fill(X + (Col - 1) * FontScale + DX,
              Y + Row * FontScale + DY, 1, 1, 0, 0, 0);
  end;
end;

procedure DrawDateSep(Buf: TPixelBuffer; P: TPainter; X, Y, Pt: Integer);
{$IFNDEF DARWIN}
var
  Scale: Integer;
{$ENDIF}
begin
  {$IFDEF DARWIN}
  DrawFace(Buf, P, X, Y, '/', Pt, False, True);
  {$ELSE}
  { Width comes from the string, so a missing glyph still left a gap.
    Paint the slash into that gap. Drawn after the digits so a part
    fill cannot cover it. }
  if Buf = nil then
    Exit;
  Scale := Pt div 7;
  if Scale < 1 then
    Scale := 1;
  DrawPixelSlash(P, X, Y, Scale);
  {$ENDIF}
end;

function PixelDateSlashInk: Integer;
var
  Buf: TPixelBuffer;
  P: TPainter;
  X, Y, TopX, BotX, N: Integer;
  Pix: PByte;
begin
  Result := 0;
  Buf := TPixelBuffer.Create(8, 8);
  P := TPainter.Create;
  try
    Buf.Clear(255, 255, 255, 255);
    P.Buf := Buf;
    P.Scale := 1;
    DrawPixelSlash(P, 0, 0, 1);
    N := 0;
    TopX := -1;
    BotX := -1;
    for Y := 0 to 6 do
      for X := 0 to 4 do
      begin
        Pix := Buf.Ptr + (Y * Buf.Width + X) * 4;
        if Pix[0] < 16 then
        begin
          Inc(N);
          if (Y <= 1) and (X > TopX) then
            TopX := X;
          if (Y >= 5) and ((BotX < 0) or (X < BotX)) then
            BotX := X;
        end;
      end;
    if (N >= 10) and (TopX > BotX) then
      Result := N;
  finally
    P.Free;
    Buf.Free;
  end;
end;

procedure DrawPart(Buf: TPixelBuffer; P: TPainter; const R: TRectI; const Text: string;
  Invert: Boolean; Pt, RowHeight: Integer);
var
  FontH, GY: Integer;
begin
  if (Text = '') or (R.R <= R.L) then
    Exit;
  FontH := AlarmTextHeight(Pt);
  GY := R.T + (RowHeight - FontH) div 2;
  if GY < R.T then
    GY := R.T;
  if Invert then
    P.Fill(R.L - 1, GY - 1, (R.R - R.L) + 2, FontH + 2, 0, 0, 0);
  DrawFace(Buf, P, R.L, GY, Text, Pt, Invert, True);
end;

procedure DrawBigTime(Buf: TPixelBuffer; P: TPainter; const V: TAlarmView);
var
  S: string;
  TW, TH, X, Y, AreaLeft, AreaRight: Integer;
  Lay: TAlarmLayout;
begin
  S := HourPlain(V.Hour12) + ':' + TwoDigits(V.Minute) + ':' + TwoDigits(V.Second) +
    ' ' + AmPmText(V.IsPM);
  TW := FaceWidth(S, BigPt);
  TH := AlarmTextHeight(BigPt);
  Lay := BuildLayout(V);
  AreaLeft := Lay.Close.R + 4;
  AreaRight := Lay.Lever.L - 4;
  { Centred in the gap between the close square and the key. }
  X := AreaLeft + (AreaRight - AreaLeft - TW) div 2;
  if X + TW > AreaRight then
    X := AreaRight - TW;
  if X < AreaLeft then
    X := AreaLeft;
  Y := TimeBandTop + (TimeBandH - TH) div 2;
  if V.Ringing and V.BlinkOn then
  begin
    { Inverted plaque: stand-in for the menu-bar flash. The original
      swapped the Apple mark and an alarm glyph; we do not draw Apple's
      logo. }
    P.Fill(X - 3, Y - 1, TW + 6, TH + 2, 0, 0, 0);
    DrawFace(Buf, P, X, Y, S, BigPt, True, True);
  end
  else
    DrawFace(Buf, P, X, Y, S, BigPt, False, True);
  if V.UsingOffset then
  begin
    { Not on the 1984 clock. The original really changed the Mac's time,
      so it had nothing to badge. This mark means the session offset is on. }
    DrawFace(Buf, P, AreaLeft, TimeBandTop, 'SET', SetPt, False, False);
  end;
end;

procedure RenderAlarm(Buf: TPixelBuffer; const V: TAlarmView; PixelScale: Integer);
var
  P: TPainter;
  Lay: TAlarmLayout;
  Thick, GY: Integer;
  InkByte: Byte;
begin
  if PixelScale < 1 then
    PixelScale := 1;
  Buf.Clear(255, 255, 255, 255);
  P := TPainter.Create;
  try
    P.Buf := Buf;
    P.Scale := PixelScale;
    Lay := BuildLayout(V);
    Thick := 1;
    DrawBigTime(Buf, P, V);
    DrawLever(P, Lay.Lever, V.Expanded);
    DrawClose(P, Lay.Close);
    if not V.Expanded then
    begin
      { Hairline is the panel edge, not a system window frame. }
      P.Stroke(0, 0, AlarmContentW, AlarmContentH(False), Thick, 0, 0, 0);
      Exit;
    end;
    { The compact bottom edge stays put and becomes the rule under the time. }
    P.Fill(1, CompactH - 1, AlarmContentW - 2, 1, 0, 0, 0);
    P.Fill(1, Lay.TimeButton.T, AlarmContentW - 2, 1, 0, 0, 0);
    P.Fill(Lay.TimeButton.R, Lay.TimeButton.T, 1, IconH, 0, 0, 0);
    P.Fill(Lay.DateButton.R, Lay.DateButton.T, 1, IconH, 0, 0, 0);
    if V.Row = rowTime then
      P.Fill(Lay.TimeButton.L + 1, Lay.TimeButton.T + 1,
        (Lay.TimeButton.R - Lay.TimeButton.L) - 1, IconH - 1, 0, 0, 0);
    if V.Row = rowDate then
      P.Fill(Lay.DateButton.L + 1, Lay.DateButton.T + 1,
        (Lay.DateButton.R - Lay.DateButton.L) - 1, IconH - 1, 0, 0, 0);
    if V.Row = rowAlarm then
      P.Fill(Lay.AlarmButton.L + 1, Lay.AlarmButton.T + 1,
        (Lay.AlarmButton.R - Lay.AlarmButton.L) - 1, IconH - 1, 0, 0, 0);
    if V.Row = rowTime then
      InkByte := 255
    else
      InkByte := 0;
    DrawClockIcon(P, Lay.TimeButton, InkByte);
    DrawCalendarBtn(P, Lay.DateButton, V.Row = rowDate);
    if V.Row = rowAlarm then
      InkByte := 255
    else
      InkByte := 0;
    DrawAlarmIcon(P, Lay.AlarmButton, InkByte);
    DrawSwitch(P, Lay.Switch, V.SwitchUp, 0);
    GY := Lay.AlarmRowTop + (ValueH - AlarmTextHeight(PanelPt)) div 2;
    if (V.Row = rowDate) or (V.Row = rowNone) then
    begin
      DrawPart(Buf, P, Lay.DateMonth, Shown(V, hitDateMonth, IntToStr(V.Month)),
        Lay.Active = hitDateMonth, PanelPt, ValueH);
      DrawPart(Buf, P, Lay.DateDay, Shown(V, hitDateDay, IntToStr(V.Day)),
        Lay.Active = hitDateDay, PanelPt, ValueH);
      DrawPart(Buf, P, Lay.DateYear, Shown(V, hitDateYear, Year2(V.Year)),
        Lay.Active = hitDateYear, PanelPt, ValueH);
      { After the digits, so the marks sit in the gaps instead of under them. }
      DrawDateSep(Buf, P, Lay.DateMonth.R, GY, PanelPt);
      DrawDateSep(Buf, P, Lay.DateDay.R, GY, PanelPt);
    end
    else if V.Row = rowTime then
    begin
      DrawPart(Buf, P, Lay.TimeHour, Shown(V, hitTimeHour, HourPlain(V.Hour12)),
        Lay.Active = hitTimeHour, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.TimeHour.R, GY, ':', PanelPt, False, True);
      DrawPart(Buf, P, Lay.TimeMinute, Shown(V, hitTimeMinute, TwoDigits(V.Minute)),
        Lay.Active = hitTimeMinute, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.TimeMinute.R, GY, ':', PanelPt, False, True);
      DrawPart(Buf, P, Lay.TimeSecond, Shown(V, hitTimeSecond, TwoDigits(V.Second)),
        Lay.Active = hitTimeSecond, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.TimeSecond.R, GY, ' ', PanelPt, False, True);
      DrawPart(Buf, P, Lay.TimeAmPm, Shown(V, hitTimeAmPm, AmPmText(V.IsPM)),
        Lay.Active = hitTimeAmPm, PanelPt, ValueH);
    end
    else
    begin
      DrawPart(Buf, P, Lay.AlarmHour, Shown(V, hitAlarmHour, HourPlain(V.AlarmH)),
        Lay.Active = hitAlarmHour, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.AlarmHour.R, GY, ':', PanelPt, False, True);
      DrawPart(Buf, P, Lay.AlarmMinute, Shown(V, hitAlarmMinute, TwoDigits(V.AlarmM)),
        Lay.Active = hitAlarmMinute, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.AlarmMinute.R, GY, ':', PanelPt, False, True);
      DrawPart(Buf, P, Lay.AlarmSecond, Shown(V, hitAlarmSecond, TwoDigits(V.AlarmS)),
        Lay.Active = hitAlarmSecond, PanelPt, ValueH);
      DrawFace(Buf, P, Lay.AlarmSecond.R, GY, ' ', PanelPt, False, True);
      DrawPart(Buf, P, Lay.AlarmAmPm, Shown(V, hitAlarmAmPm, AmPmText(V.AlarmPM)),
        Lay.Active = hitAlarmAmPm, PanelPt, ValueH);
    end;
    if Lay.ArrowsVisible then
      DrawArrows(P, Lay.ArrowUp, Lay.ArrowDown);
    { Edge last, so a selected picture cannot paint over the border. }
    P.Stroke(0, 0, AlarmContentW, AlarmContentH(True), Thick, 0, 0, 0);
  finally
    P.Free;
  end;
end;

end.
