unit uhostcocoa;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

{ macOS window for the Alarm Clock. Borderless: the painted face is the
  window, with no title bar. The lever changes the height and the top
  edge stays put. Empty pixels drag the panel; the drawn close mark quits.
  The Alarm Clock menu (About, Use System Time, Quit) stays in the menu bar.

  Regular activation policy so there is a Dock icon. Catalina (10.15) and
  Sonoma both have these AppKit calls; the plist asks for 10.13 or newer.
  Pixel scale is rounded to an integer so the 5×7 font is not filtered. }

interface

procedure HostRun;

implementation

uses
  SysUtils, CocoaAll, ualarmapp;

type
  TAlarmView = objcclass;
  TAlarmWindow = objcclass;

  NSBitmapImageRepAlarm = objccategory external (NSBitmapImageRep)
    function initRGBA(planes: Pointer; aWidth: NSInteger; aHeight: NSInteger;
      aBits: NSInteger; aSamples: NSInteger; aAlpha: ObjCBOOL;
      aPlanar: ObjCBOOL; aSpace: NSString; aBpr: NSInteger;
      aBpp: NSInteger): id; message 'initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:';
  end;

  TAppDelegate = objcclass(NSObject, NSApplicationDelegateProtocol, NSWindowDelegateProtocol)
  public
    controller: TAlarmController;
    window: TAlarmWindow;
    view: TAlarmView;
    frameImage: NSImage;
    animTimer: NSTimer;
    scale: Integer;
    ready: ObjCBOOL;
    procedure applicationDidFinishLaunching(notification: NSNotification); message 'applicationDidFinishLaunching:';
    function applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL; message 'applicationShouldTerminateAfterLastWindowClosed:';
    procedure quitAction(sender: id); message 'quitAction:';
    procedure aboutAction(sender: id); message 'aboutAction:';
    procedure resetAction(sender: id); message 'resetAction:';
    procedure windowWillClose(notification: NSNotification); message 'windowWillClose:';
    procedure tick(timer: NSTimer); message 'tick:';
    procedure redraw; message 'redraw';
    procedure applyChrome; message 'applyChrome';
    procedure setup; message 'setup';
  end;

  TAlarmWindow = objcclass(NSWindow)
  public
    app: TAppDelegate;
    function canBecomeKeyWindow: ObjCBOOL; override;
    function canBecomeMainWindow: ObjCBOOL; override;
  end;

  TAlarmView = objcclass(NSView)
  public
    app: TAppDelegate;
    dragging: ObjCBOOL;
    dragScreenX, dragScreenY: Double;
    dragFrameX, dragFrameY: Double;
    procedure drawRect(dirtyRect: NSRect); override;
    function acceptsFirstResponder: ObjCBOOL; override;
    function acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL; override;
    procedure mouseDown(event: NSEvent); override;
    procedure mouseDragged(event: NSEvent); override;
    procedure mouseUp(event: NSEvent); override;
    procedure mouseMoved(event: NSEvent); override;
    procedure keyDown(event: NSEvent); override;
    function logicalX(event: NSEvent): Integer; message 'logicalX:';
    function logicalY(event: NSEvent): Integer; message 'logicalY:';
    procedure updateCursor(event: NSEvent); message 'updateCursor:';
  end;

var
  SharedApp: TAppDelegate;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

procedure NSBeep; cdecl; external 'AppKit' name 'NSBeep';

function MakeImage(Pixels: PByte; PixelW, PixelH: Integer; PointW, PointH: Double): NSImage;
var
  Rep: NSBitmapImageRep;
  Dest: PByte;
  Bytes: Integer;
begin
  Rep := NSBitmapImageRep(NSBitmapImageRep.alloc.initRGBA(nil, PixelW, PixelH, 8, 4,
    True, False, NSCalibratedRGBColorSpace, PixelW * 4, 32));
  { nil planes: AppKit owns a snapshot. Aliasing Canvas.Ptr would freeze the first second. }
  Result := NSImage.alloc.initWithSize(NSMakeSize(PointW, PointH));
  if Rep <> nil then
  begin
    Dest := PByte(Rep.bitmapData);
    Bytes := PixelW * PixelH * 4;
    if (Dest <> nil) and (Pixels <> nil) and (Bytes > 0) then
      Move(Pixels^, Dest^, Bytes);
    Result.addRepresentation(Rep);
    Rep.release;
  end;
  Result.setCacheMode(NSImageCacheNever);
end;

procedure TAppDelegate.redraw;
var
  B: NSRect;
begin
  if (controller = nil) or (view = nil) then
    Exit;
  controller.Render;
  B := view.bounds;
  if frameImage <> nil then
    frameImage.release;
  frameImage := MakeImage(controller.Canvas.Ptr, controller.Canvas.Width,
    controller.Canvas.Height, B.size.width, B.size.height);
  controller.ConsumePresent;
  view.setNeedsDisplay_(True);
end;

procedure TAppDelegate.applyChrome;
var
  Frame, Content: NSRect;
  Top: Double;
  W, H: Integer;
begin
  if (window = nil) or (controller = nil) then
    Exit;
  controller.ApplyChrome;
  W := controller.ContentWidth;
  H := controller.ContentHeight;
  Frame := window.frame;
  { Keep the top edge. setContentSize would grow upward, under the menu bar.
    The desk accessory grew downward from the title. }
  Top := Frame.origin.y + Frame.size.height;
  Content := window.contentRectForFrameRect(Frame);
  Content.size.width := W;
  Content.size.height := H;
  Content.origin.x := Frame.origin.x;
  Frame := window.frameRectForContentRect(Content);
  Frame.origin.y := Top - Frame.size.height;
  Frame.origin.x := window.frame.origin.x;
  window.setFrame_display(Frame, True);
end;

procedure TAppDelegate.tick(timer: NSTimer);
var
  Pool: NSAutoreleasePool;
begin
  Pool := NSAutoreleasePool.alloc.init;
  if controller <> nil then
  begin
    controller.Tick;
    if controller.ConsumeBeep then
      NSBeep;
    if controller.WantsResize then
      applyChrome;
    if controller.NeedsPresent then
      redraw;
  end;
  Pool.release;
end;

procedure SetupMenu(Del: TAppDelegate);
var
  MainMenu, AppMenu: NSMenu;
  AppItem, Item: NSMenuItem;
begin
  MainMenu := NSMenu.alloc.init;

  AppItem := NSMenuItem.alloc.init;
  AppMenu := NSMenu.alloc.initWithTitle(NSStr('Alarm Clock'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('About Alarm Clock'), objcselector('aboutAction:'), NSStr(''));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Use System Time'), objcselector('resetAction:'), NSStr(''));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppMenu.addItem(NSMenuItem.separatorItem);
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Quit Alarm Clock'), objcselector('quitAction:'), NSStr('q'));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppItem.setSubmenu(AppMenu);
  MainMenu.addItem(AppItem);

  NSApplication.sharedApplication.setMainMenu(MainMenu);
  AppMenu.release;
  AppItem.release;
  MainMenu.release;
end;

procedure TAppDelegate.setup;
var
  PixelScale: Double;
  Style: NSUInteger;
  Rect, Vis: NSRect;
  W, H: Integer;
begin
  if ready then
    Exit;
  ready := True;

  PixelScale := 2;
  if NSScreen.mainScreen <> nil then
    PixelScale := NSScreen.mainScreen.backingScaleFactor;
  { Integer scale: a 2× retina buffer, or 1× on a non-retina Catalina Mac.
    A fractional scale would blur the pixel font. }
  scale := Round(PixelScale);
  if scale < 1 then
    scale := 1;

  controller := TAlarmController.Create(scale, AlarmSettingsFile);
  W := controller.ContentWidth;
  H := controller.ContentHeight;

  SetupMenu(self);

  { No title bar. The canvas is the window. }
  Style := NSBorderlessWindowMask;
  Rect := NSMakeRect(80, 80, W, H);
  if NSScreen.mainScreen <> nil then
  begin
    { Upper right, just under the menu bar. The LC manual put it there. }
    Vis := NSScreen.mainScreen.visibleFrame;
    Rect := NSMakeRect(
      Vis.origin.x + Vis.size.width - W - 18,
      Vis.origin.y + Vis.size.height - H - 12,
      W, H);
  end;
  window := TAlarmWindow.alloc.initWithContentRect_styleMask_backing_defer(
    Rect, Style, NSBackingStoreBuffered, False);
  window.app := self;
  window.setReleasedWhenClosed(False);
  window.setOpaque(True);
  window.setHasShadow(True);
  window.setBackgroundColor(NSColor.whiteColor);
  window.setAcceptsMouseMovedEvents(True);
  window.setDelegate(self);

  view := TAlarmView.alloc.initWithFrame(NSMakeRect(0, 0, W, H));
  view.app := self;
  window.setContentView(view);
  window.makeFirstResponder(view);

  redraw;

  animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
    0.1, self, objcselector('tick:'), nil, True);
  animTimer.retain;
  NSRunLoop.currentRunLoop.addTimer_forMode(animTimer, NSRunLoopCommonModes);

  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
  window.makeKeyAndOrderFront(nil);
end;

procedure TAppDelegate.applicationDidFinishLaunching(notification: NSNotification);
begin
  setup;
end;

function TAppDelegate.applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL;
begin
  Result := True;
end;

procedure TAppDelegate.windowWillClose(notification: NSNotification);
begin
  { State change: close box. Commit a half-edited alarm, then the process ends. }
  if controller <> nil then
    controller.CommitForClose;
end;

procedure TAppDelegate.quitAction(sender: id);
begin
  if controller <> nil then
    controller.CommitForClose;
  NSApplication.sharedApplication.terminate(nil);
end;

procedure TAppDelegate.aboutAction(sender: id);
var
  Alert: NSAlert;
begin
  Alert := NSAlert.alloc.init;
  Alert.setMessageText(NSStr(AlarmAboutTitle));
  Alert.setInformativeText(NSStr(AlarmAboutText));
  Alert.runModal;
  Alert.release;
end;

procedure TAppDelegate.resetAction(sender: id);
begin
  if controller = nil then
    Exit;
  { State change lives in ResetToSystem: offset back to zero, no false ring. }
  controller.Model.ResetToSystem;
  controller.Model.ClearDirty;
  redraw;
end;

function TAlarmView.logicalX(event: NSEvent): Integer;
var
  P: NSPoint;
begin
  P := self.convertPoint_fromView(event.locationInWindow, nil);
  Result := Trunc(P.x);
end;

function TAlarmView.logicalY(event: NSEvent): Integer;
var
  P: NSPoint;
begin
  { This view is not flipped: AppKit's y grows upward, the canvas grows down. }
  P := self.convertPoint_fromView(event.locationInWindow, nil);
  Result := Trunc(self.bounds.size.height - P.y);
end;

procedure TAlarmView.updateCursor(event: NSEvent);
begin
  if (app = nil) or (app.controller = nil) or (event = nil) then
    Exit;
  { FPC renames NSCursor's `set` to set_ because set is a Pascal keyword. }
  if app.controller.WantsCrosshair(logicalX(event), logicalY(event)) then
    NSCursor.crosshairCursor.set_
  else
    NSCursor.arrowCursor.set_;
end;

procedure TAlarmView.drawRect(dirtyRect: NSRect);
begin
  NSColor.whiteColor.set_;
  NSRectFill(self.bounds);
  if (app = nil) or (app.frameImage = nil) then
    Exit;
  app.frameImage.drawInRect_fromRect_operation_fraction(self.bounds, NSZeroRect,
    NSCompositeSourceOver, 1.0);
end;

function TAlarmView.acceptsFirstResponder: ObjCBOOL;
begin
  Result := True;
end;

function TAlarmView.acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TAlarmView.mouseDown(event: NSEvent);
var
  P: NSPoint;
begin
  dragging := False;
  if (app = nil) or (app.controller = nil) or (event = nil) then
    Exit;
  self.window.makeFirstResponder(self);
  { A double-click delivers a second mouseDown with clickCount 2.
    Acting on both would open the lever and immediately close it. }
  if event.clickCount > 1 then
    Exit;
  if app.controller.PointerDown(logicalX(event), logicalY(event)) then
  begin
    { Empty pixels drag the borderless panel. }
    P := self.window.convertBaseToScreen(event.locationInWindow);
    dragging := True;
    dragScreenX := P.x;
    dragScreenY := P.y;
    dragFrameX := self.window.frame.origin.x;
    dragFrameY := self.window.frame.origin.y;
    Exit;
  end;
  if app.controller.WantsQuit then
  begin
    app.quitAction(nil);
    Exit;
  end;
  if app.controller.WantsResize then
    app.applyChrome;
  if app.controller.NeedsPresent then
    app.redraw;
end;

procedure TAlarmView.mouseDragged(event: NSEvent);
var
  P: NSPoint;
  F: NSRect;
begin
  if (not dragging) or (event = nil) or (self.window = nil) then
    Exit;
  P := self.window.convertBaseToScreen(event.locationInWindow);
  F := self.window.frame;
  F.origin.x := dragFrameX + (P.x - dragScreenX);
  F.origin.y := dragFrameY + (P.y - dragScreenY);
  self.window.setFrame_display(F, True);
end;

procedure TAlarmView.mouseUp(event: NSEvent);
begin
  dragging := False;
end;

procedure TAlarmView.mouseMoved(event: NSEvent);
begin
  updateCursor(event);
end;

procedure TAlarmView.keyDown(event: NSEvent);
var
  Code: Word;
  Chars: string;
  C: Char;
begin
  if (app = nil) or (app.controller = nil) or (event = nil) then
    Exit;
  Code := event.keyCode;
  case Code of
    126: app.controller.Key(akUp, 0);       { up arrow }
    125: app.controller.Key(akDown, 0);
    123: app.controller.Key(akLeft, 0);
    124: app.controller.Key(akRight, 0);
    48:  app.controller.Key(akTab, 0);
    53:  app.controller.Key(akEscape, 0);
    36, 76: app.controller.Key(akReturn, 0);  { return, keypad enter }
  else
    begin
      if event.characters <> nil then
        Chars := event.characters.UTF8String
      else
        Chars := '';
      if Chars <> '' then
      begin
        C := Chars[1];
        if (C >= '0') and (C <= '9') then
          app.controller.Key(akDigit, Ord(C) - Ord('0'))
        else if ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) then
          app.controller.Key(akLetter, Ord(C))
        else
          Exit;
      end
      else
        Exit;
    end;
  end;
  if app.controller.WantsResize then
    app.applyChrome;
  if app.controller.NeedsPresent then
    app.redraw;
end;

function TAlarmWindow.canBecomeKeyWindow: ObjCBOOL;
begin
  { Borderless windows refuse key focus unless they say yes. }
  Result := True;
end;

function TAlarmWindow.canBecomeMainWindow: ObjCBOOL;
begin
  { Same for the menu bar: About, Use System Time, and Quit. }
  Result := True;
end;

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

end.
