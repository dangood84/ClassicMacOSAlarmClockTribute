unit ualarmtext;

{$mode objfpc}{$H+}
{$IFDEF DARWIN}
{$modeswitch objectivec1}
{$ENDIF}

{ Measures and draws the Alarm Clock's words.

  On a Mac the face is Geneva, the system font the original desk
  accessories were set in. Geneva has no bold outline, so the time and
  the date are drawn twice, one pixel apart. The file stays in the OS
  font folder; this unit asks AppKit to draw it and does not embed
  Apple's outlines.

  Other hosts have no Geneva. They keep a width that matches the 5×7
  pixel face ualarmrender already draws. }

interface

uses
  ualarmrender;

function AlarmTextWidth(const S: string; Pt: Integer; Bold: Boolean): Integer;
function AlarmTextHeight(Pt: Integer): Integer;
procedure AlarmDrawText(Buf: TPixelBuffer; X, Y, PixelScale: Integer;
  const S: string; Pt: Integer; WhiteInk, Bold: Boolean);

implementation

{$IFDEF DARWIN}

uses
  CocoaAll, SysUtils;

type
  NSBitmapImageRepText = objccategory external (NSBitmapImageRep)
    function initRGBA(planes: Pointer; aWidth: NSInteger; aHeight: NSInteger;
      aBits: NSInteger; aSamples: NSInteger; aAlpha: ObjCBOOL;
      aPlanar: ObjCBOOL; aSpace: NSString; aBpr: NSInteger;
      aBpp: NSInteger): id; message 'initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:';
  end;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

function FontOf(Pt: Integer): NSFont;
begin
  Result := NSFont.fontWithName_size(NSStr('Geneva'), Pt);
  if Result = nil then
    Result := NSFont.systemFontOfSize(Pt);
end;

function AttrOf(Font: NSFont; WhiteInk: Boolean): NSMutableDictionary;
var
  Ink: NSColor;
begin
  Result := NSMutableDictionary.alloc.init;
  Result.setObject_forKey(Font, NSFontAttributeName);
  if WhiteInk then
    Ink := NSColor.whiteColor
  else
    Ink := NSColor.blackColor;
  Result.setObject_forKey(Ink, NSForegroundColorAttributeName);
end;

function AlarmTextWidth(const S: string; Pt: Integer; Bold: Boolean): Integer;
var
  Pool: NSAutoreleasePool;
  Font: NSFont;
  Attr: NSMutableDictionary;
  Sz: NSSize;
begin
  if (S = '') or (Pt < 1) then
    Exit(0);
  Pool := NSAutoreleasePool.alloc.init;
  Font := FontOf(Pt);
  Attr := AttrOf(Font, False);
  Sz := NSStr(S).sizeWithAttributes(Attr);
  { Geneva ships with no bold face. A one-pixel smear is the weight. }
  Result := Trunc(Sz.width + 0.999);
  if Bold then
    Inc(Result);
  if Result < 1 then
    Result := 1;
  Attr.release;
  Pool.release;
end;

function AlarmTextHeight(Pt: Integer): Integer;
var
  Pool: NSAutoreleasePool;
  Font: NSFont;
begin
  if Pt < 1 then
    Exit(0);
  Pool := NSAutoreleasePool.alloc.init;
  Font := FontOf(Pt);
  Result := Trunc(Font.ascender - Font.descender + Font.leading + 0.999);
  if Result < 1 then
    Result := Pt;
  Pool.release;
end;

procedure AlarmDrawText(Buf: TPixelBuffer; X, Y, PixelScale: Integer;
  const S: string; Pt: Integer; WhiteInk, Bold: Boolean);
var
  Pool: NSAutoreleasePool;
  Font: NSFont;
  Attr: NSMutableDictionary;
  Str: NSString;
  Sz: NSSize;
  PixW, PixH, PtPix, Baseline: Integer;
  Rep: NSBitmapImageRep;
  Ctx: NSGraphicsContext;
  Src: PByte;
  Row, Col, DX, DY, DestX, DestY: Integer;
  P: PByte;
begin
  if (Buf = nil) or (Buf.Ptr = nil) or (S = '') or (Pt < 1) then
    Exit;
  if PixelScale < 1 then
    PixelScale := 1;
  Pool := NSAutoreleasePool.alloc.init;
  PtPix := Pt * PixelScale;
  Font := FontOf(PtPix);
  Attr := AttrOf(Font, WhiteInk);
  Str := NSStr(S);
  Sz := Str.sizeWithAttributes(Attr);
  PixW := Trunc(Sz.width + 0.999) + 1;
  if Bold then
    Inc(PixW, PixelScale);
  PixH := Trunc(Font.ascender - Font.descender + Font.leading + 0.999) + 1;
  if PixW < 1 then
    PixW := 1;
  if PixH < 1 then
    PixH := 1;
  Rep := NSBitmapImageRep(NSBitmapImageRep.alloc.initRGBA(nil, PixW, PixH, 8, 4,
    True, False, NSCalibratedRGBColorSpace, PixW * 4, 32));
  if Rep <> nil then
  begin
    Ctx := NSGraphicsContext.graphicsContextWithBitmapImageRep(Rep);
    NSGraphicsContext.classSaveGraphicsState;
    NSGraphicsContext.setCurrentContext(Ctx);
    { Classic Mac type is 1-bit. Outline Geneva would otherwise soften. }
    Ctx.setShouldAntialias(False);
    NSColor.clearColor.set_;
    NSRectFill(NSMakeRect(0, 0, PixW, PixH));
    { Bitmap context origin is the bottom left. The baseline sits one
      descender up from that, which lands the glyphs in the buffer. }
    Baseline := Trunc(-Font.descender + 0.5);
    Str.drawAtPoint_withAttributes(NSMakePoint(0, Baseline), Attr);
    if Bold then
      Str.drawAtPoint_withAttributes(NSMakePoint(PixelScale, Baseline), Attr);
    NSGraphicsContext.classRestoreGraphicsState;
    Src := PByte(Rep.bitmapData);
    if Src <> nil then
    begin
      DX := X * PixelScale;
      DY := Y * PixelScale;
      for Row := 0 to PixH - 1 do
        for Col := 0 to PixW - 1 do
        begin
          P := Src + (Row * PixW + Col) * 4;
          if P[3] < 96 then
            Continue;
          DestX := DX + Col;
          DestY := DY + Row;
          if (DestX < 0) or (DestY < 0) or (DestX >= Buf.Width) or (DestY >= Buf.Height) then
            Continue;
          if WhiteInk then
          begin
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4] := 255;
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4 + 1] := 255;
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4 + 2] := 255;
          end
          else
          begin
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4] := 0;
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4 + 1] := 0;
            PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4 + 2] := 0;
          end;
          PByte(Buf.Ptr)[(DestY * Buf.Width + DestX) * 4 + 3] := 255;
        end;
    end;
    Rep.release;
  end;
  Attr.release;
  Pool.release;
end;

{$ELSE}

function AlarmTextWidth(const S: string; Pt: Integer; Bold: Boolean): Integer;
var
  Scale: Integer;
begin
  Scale := Pt div 7;
  if Scale < 1 then
    Scale := 1;
  if S = '' then
    Exit(0);
  Result := Length(S) * 5 * Scale + (Length(S) - 1) * Scale;
  if Bold then
    Inc(Result, Scale);
end;

function AlarmTextHeight(Pt: Integer): Integer;
var
  Scale: Integer;
begin
  Scale := Pt div 7;
  if Scale < 1 then
    Scale := 1;
  Result := 7 * Scale;
end;

procedure AlarmDrawText(Buf: TPixelBuffer; X, Y, PixelScale: Integer;
  const S: string; Pt: Integer; WhiteInk, Bold: Boolean);
begin
  { ualarmrender draws the 5×7 face on hosts that have no Geneva. }
end;

{$ENDIF}

end.
