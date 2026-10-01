unit uhostwin;

{$mode objfpc}{$H+}

{ Windows borderless panel on the taskbar. Same TAlarmController as macOS.
  No caption: the painted face is the window. Empty pixels drag it, the
  drawn close mark quits, and a right-click menu holds About, Use System
  Time, and Exit. The lever changes the client height and the top-left
  corner stays put. Boot Camp on the 2014 Mac is this path. }

interface

procedure HostRun;

implementation

{$IFDEF WINDOWS}

uses
  Windows, Messages, SysUtils, ualarmapp, ualarmrender;

const
  AppName = 'AlarmClockWnd';
  CmdAbout = 1001;
  CmdQuit = 1002;
  CmdReset = 1003;
  TickId = 1;
  TickMs = 100;

var
  Controller: TAlarmController;
  MainWnd: HWND;
  Bgra: array of Byte;
  PopupMenu: HMENU;
  LastX, LastY: Integer;

procedure Present(Wnd: HWND);
begin
  Controller.Render;
  SetLength(Bgra, Controller.Canvas.Width * Controller.Canvas.Height * 4);
  CopyBGRA(Controller.Canvas, @Bgra[0]);
  Controller.ConsumePresent;
  InvalidateRect(Wnd, nil, False);
end;

procedure PaintClock(Wnd: HWND);
var
  PS: PAINTSTRUCT;
  DC: HDC;
  Info: BITMAPINFO;
  R: TRect;
begin
  DC := BeginPaint(Wnd, @PS);
  GetClientRect(Wnd, @R);
  if Length(Bgra) = Controller.Canvas.Width * Controller.Canvas.Height * 4 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
    Info.bmiHeader.biWidth := Controller.Canvas.Width;
    Info.bmiHeader.biHeight := -Controller.Canvas.Height; { top-down DIB }
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    StretchDIBits(DC, 0, 0, R.Right - R.Left, R.Bottom - R.Top,
      0, 0, Controller.Canvas.Width, Controller.Canvas.Height,
      @Bgra[0], Info, DIB_RGB_COLORS, SRCCOPY);
  end;
  EndPaint(Wnd, @PS);
end;

procedure ApplyChrome(Wnd: HWND);
var
  Style: DWORD;
  Outer, Current: TRect;
  NewW, NewH: Integer;
begin
  { State change: lever. Rebuild the buffer, then the window, top-left fixed. }
  Controller.ApplyChrome;
  Style := GetWindowLong(Wnd, GWL_STYLE);
  Outer := Rect(0, 0, Controller.ContentWidth, Controller.ContentHeight);
  AdjustWindowRect(Outer, Style, False);
  NewW := Outer.Right - Outer.Left;
  NewH := Outer.Bottom - Outer.Top;
  GetWindowRect(Wnd, Current);
  MoveWindow(Wnd, Current.Left, Current.Top, NewW, NewH, True);
  Present(Wnd);
end;

procedure ShowAbout(Wnd: HWND);
begin
  MessageBox(Wnd, PChar(AlarmAboutText), AlarmAboutTitle, MB_OK or MB_ICONINFORMATION);
end;

function BuildPopup: HMENU;
begin
  { No menu bar on the frame. Right-click opens this. }
  Result := CreatePopupMenu;
  AppendMenu(Result, MF_STRING, CmdAbout, '&About Alarm Clock...');
  AppendMenu(Result, MF_STRING, CmdReset, '&Use System Time');
  AppendMenu(Result, MF_SEPARATOR, 0, nil);
  AppendMenu(Result, MF_STRING, CmdQuit, 'E&xit');
end;

procedure HandleKey(Wnd: HWND; Virt: WPARAM; ScanChar: Char);
begin
  case Virt of
    VK_UP: Controller.Key(akUp, 0);
    VK_DOWN: Controller.Key(akDown, 0);
    VK_LEFT: Controller.Key(akLeft, 0);
    VK_RIGHT: Controller.Key(akRight, 0);
    VK_TAB: Controller.Key(akTab, 0);
    VK_ESCAPE: Controller.Key(akEscape, 0);
    VK_RETURN: Controller.Key(akReturn, 0);
  else
    if (ScanChar >= '0') and (ScanChar <= '9') then
      Controller.Key(akDigit, Ord(ScanChar) - Ord('0'))
    else if ((ScanChar >= 'a') and (ScanChar <= 'z')) or
            ((ScanChar >= 'A') and (ScanChar <= 'Z')) then
      Controller.Key(akLetter, Ord(ScanChar))
    else
      Exit;
  end;
  if Controller.WantsResize then
    ApplyChrome(Wnd)
  else if Controller.NeedsPresent then
    Present(Wnd);
end;

function WndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  X, Y: Integer;
  Pt: TPoint;
begin
  Result := 0;
  case Msg of
    WM_CREATE:
      begin
        SetTimer(Wnd, TickId, TickMs, nil);
        Present(Wnd);
      end;
    WM_TIMER:
      if WParam = TickId then
      begin
        Controller.Tick;
        if Controller.ConsumeBeep then
          MessageBeep(MB_ICONEXCLAMATION);
        if Controller.WantsResize then
          ApplyChrome(Wnd)
        else if Controller.NeedsPresent then
          Present(Wnd);
      end;
    WM_PAINT:
      PaintClock(Wnd);
    WM_LBUTTONDOWN:
      begin
        X := Smallint(LOWORD(LParam));
        Y := Smallint(HIWORD(LParam));
        SetFocus(Wnd);
        if Controller.PointerDown(X, Y) then
        begin
          { Empty pixels: drag the borderless window by its client. }
          ReleaseCapture;
          SendMessage(Wnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        end
        else if Controller.WantsQuit then
          PostQuitMessage(0)
        else if Controller.WantsResize then
          ApplyChrome(Wnd)
        else if Controller.NeedsPresent then
          Present(Wnd);
      end;
    WM_RBUTTONDOWN:
      begin
        Pt.X := Smallint(LOWORD(LParam));
        Pt.Y := Smallint(HIWORD(LParam));
        ClientToScreen(Wnd, Pt);
        TrackPopupMenu(PopupMenu, TPM_LEFTALIGN or TPM_RIGHTBUTTON, Pt.X, Pt.Y, 0, Wnd, nil);
      end;
    WM_MOUSEMOVE:
      begin
        LastX := Smallint(LOWORD(LParam));
        LastY := Smallint(HIWORD(LParam));
      end;
    WM_SETCURSOR:
      begin
        if LOWORD(LParam) = HTCLIENT then
        begin
          { The manual's crosshair, on the line under the time. }
          if Controller.WantsCrosshair(LastX, LastY) then
            SetCursor(LoadCursor(0, IDC_CROSS))
          else
            SetCursor(LoadCursor(0, IDC_ARROW));
          Result := 1;
          Exit;
        end;
        Result := DefWindowProc(Wnd, Msg, WParam, LParam);
      end;
    WM_KEYDOWN:
      HandleKey(Wnd, WParam, #0);
    WM_CHAR:
      if (WParam >= 32) and (WParam < 127) then
        HandleKey(Wnd, 0, Char(WParam));
    WM_COMMAND:
      case LOWORD(WParam) of
        CmdAbout:
          ShowAbout(Wnd);
        CmdReset:
          begin
            Controller.Model.ResetToSystem;
            Controller.Model.ClearDirty;
            Present(Wnd);
          end;
        CmdQuit:
          begin
            Controller.CommitForClose;
            PostQuitMessage(0);
          end;
      end;
    WM_CLOSE:
      begin
        Controller.CommitForClose;
        DestroyWindow(Wnd);
      end;
    WM_DESTROY:
      begin
        KillTimer(Wnd, TickId);
        PostQuitMessage(0);
      end;
    else
      Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

procedure HostRun;
var
  WC: WNDCLASS;
  Msg: TMsg;
  Wr, Work: TRect;
  Style: DWORD;
  WinW, WinH, Left, Top: Integer;
begin
  Controller := TAlarmController.Create(1, AlarmSettingsFile);
  PopupMenu := BuildPopup;

  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := GetStockObject(WHITE_BRUSH);
  WC.lpszClassName := AppName;
  RegisterClass(WC);

  Style := WS_POPUP;
  Wr := Rect(0, 0, Controller.ContentWidth, Controller.ContentHeight);
  AdjustWindowRect(Wr, Style, False);
  WinW := Wr.Right - Wr.Left;
  WinH := Wr.Bottom - Wr.Top;

  Work := Rect(0, 0, 800, 600);
  SystemParametersInfo(SPI_GETWORKAREA, 0, @Work, 0);
  { Upper right of the work area, under the taskbar's opposite corner. }
  Left := Work.Right - WinW - 16;
  Top := Work.Top + 12;

  MainWnd := CreateWindowEx(WS_EX_APPWINDOW, AppName, 'Alarm Clock',
    Style, Left, Top, WinW, WinH, 0, 0, HInstance, nil);

  ShowWindow(MainWnd, SW_SHOW);
  UpdateWindow(MainWnd);

  while GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
