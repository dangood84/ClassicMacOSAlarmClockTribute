unit uhostgtk;

{$mode objfpc}{$H+}

{ Linux GTK 2 window. Same TAlarmController as macOS. GTK 2 is the
  Raspberry Pi OS-friendly toolkit (libgtk2.0). The window is undecorated:
  the painted face is the window. Empty pixels drag it, the drawn close
  mark quits, and a right-click menu holds About, Use System Time, and
  Quit. The lever changes the drawing-area size. }

interface

procedure HostRun;

implementation

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}

uses
  SysUtils, ctypes, gtk2, gdk2, gdk2pixbuf, glib2, ualarmapp;

const
  TickMs = 100;
  GDK_KEY_Escape = $FF1B;
  GDK_KEY_Return = $FF0D;
  GDK_KEY_Tab = $FF09;
  GDK_KEY_Up = $FF52;
  GDK_KEY_Down = $FF54;
  GDK_KEY_Left = $FF51;
  GDK_KEY_Right = $FF53;
  GDK_KEY_KP_Enter = $FF8D;

var
  Controller: TAlarmController;
  MainWin: PGtkWidget;
  DrawArea: PGtkWidget;
  PopupMenu: PGtkWidget;
  Pix: PGdkPixbuf;
  CrossCursor: PGdkCursor;

procedure DestroyPix;
begin
  if Pix <> nil then
  begin
    g_object_unref(Pix);
    Pix := nil;
  end;
end;

procedure EnsurePixbuf;
begin
  if (Controller.Canvas.Width < 1) or (Controller.Canvas.Height < 1) then
    Exit;
  if (Pix <> nil) and
     (gdk_pixbuf_get_width(Pix) = Controller.Canvas.Width) and
     (gdk_pixbuf_get_height(Pix) = Controller.Canvas.Height) then
    Exit;
  DestroyPix;
  Pix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8,
    Controller.Canvas.Width, Controller.Canvas.Height);
end;

procedure PixbufFromBuffer;
var
  Pixels: PByte;
  Row: Integer;
  Src, Dst: PByte;
  BufW: Integer;
begin
  EnsurePixbuf;
  if Pix = nil then
    Exit;
  BufW := Controller.Canvas.Width;
  Pixels := PByte(gdk_pixbuf_get_pixels(Pix));
  for Row := 0 to Controller.Canvas.Height - 1 do
  begin
    Src := Controller.Canvas.Ptr + Row * BufW * 4;
    Dst := Pixels + Row * gdk_pixbuf_get_rowstride(Pix);
    Move(Src^, Dst^, BufW * 4);
  end;
end;

procedure Present;
begin
  Controller.Render;
  PixbufFromBuffer;
  Controller.ConsumePresent;
  if DrawArea <> nil then
    gtk_widget_queue_draw(DrawArea);
end;

procedure ApplyChrome;
begin
  { State change: lever. The drawing area's request changes and the
    window follows. Resizable is toggled so the WM honours the new size. }
  Controller.ApplyChrome;
  gtk_window_set_resizable(PGtkWindow(MainWin), True);
  gtk_widget_set_size_request(DrawArea, Controller.ContentWidth, Controller.ContentHeight);
  gtk_window_resize(PGtkWindow(MainWin), Controller.ContentWidth, Controller.ContentHeight);
  gtk_window_set_resizable(PGtkWindow(MainWin), False);
  Present;
end;

procedure AfterInput;
begin
  if Controller.WantsResize then
    ApplyChrome
  else if Controller.NeedsPresent then
    Present;
end;

procedure ShowAbout(Parent: PGtkWidget);
var
  Dlg: PGtkWidget;
begin
  Dlg := gtk_message_dialog_new(PGtkWindow(Parent), GTK_DIALOG_MODAL,
    GTK_MESSAGE_INFO, GTK_BUTTONS_OK, PChar(AlarmAboutText));
  gtk_window_set_title(PGtkWindow(Dlg), AlarmAboutTitle);
  gtk_dialog_run(PGtkDialog(Dlg));
  gtk_widget_destroy(Dlg);
end;

procedure OnQuit(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  Controller.CommitForClose;
  gtk_main_quit;
end;

procedure OnAbout(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  ShowAbout(MainWin);
end;

procedure OnReset(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  Controller.Model.ResetToSystem;
  Controller.Model.ClearDirty;
  Present;
end;

function OnDelete(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Controller.CommitForClose;
  gtk_main_quit;
  Result := False;
end;

function OnTick(Data: gpointer): gboolean; cdecl;
begin
  Controller.Tick;
  if Controller.ConsumeBeep then
    gdk_beep;
  if Controller.WantsResize then
    ApplyChrome
  else if Controller.NeedsPresent then
    Present;
  Result := True;
end;

function OnExpose(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  DestW, DestH: Integer;
begin
  Result := False;
  if (Pix = nil) or (Widget^.window = nil) then
    Exit;
  DestW := gdk_pixbuf_get_width(Pix);
  DestH := gdk_pixbuf_get_height(Pix);
  gdk_pixbuf_render_to_drawable(Pix, Widget^.window,
    Widget^.style^.fg_gc[GTK_WIDGET_STATE(Widget)],
    0, 0, 0, 0, DestW, DestH, GDK_RGB_DITHER_NONE, 0, 0);
end;

function OnButtonPress(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Result := True;
  if Event^.button._type <> GDK_BUTTON_PRESS then
    Exit; { ignore the second half of a double-click }
  if Event^.button.button = 3 then
  begin
    gtk_menu_popup(PGtkMenu(PopupMenu), nil, nil, nil, nil,
      Event^.button.button, Event^.button.time);
    Exit;
  end;
  if Event^.button.button <> 1 then
    Exit;
  gtk_widget_grab_focus(DrawArea);
  if Controller.PointerDown(Trunc(Event^.button.x), Trunc(Event^.button.y)) then
    gtk_window_begin_move_drag(PGtkWindow(MainWin), Event^.button.button,
      Trunc(Event^.button.x_root), Trunc(Event^.button.y_root), Event^.button.time)
  else if Controller.WantsQuit then
  begin
    Controller.CommitForClose;
    gtk_main_quit;
  end
  else
    AfterInput;
end;

function OnMotion(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Result := False;
  if (Widget = nil) or (Widget^.window = nil) then
    Exit;
  if Controller.WantsCrosshair(Trunc(Event^.motion.x), Trunc(Event^.motion.y)) then
    gdk_window_set_cursor(Widget^.window, CrossCursor)
  else
    gdk_window_set_cursor(Widget^.window, nil);
end;

function OnKey(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  KV: guint;
  Ch: Char;
begin
  Result := True;
  KV := Event^.key.keyval;
  if KV = GDK_KEY_Up then
    Controller.Key(akUp, 0)
  else if KV = GDK_KEY_Down then
    Controller.Key(akDown, 0)
  else if KV = GDK_KEY_Left then
    Controller.Key(akLeft, 0)
  else if KV = GDK_KEY_Right then
    Controller.Key(akRight, 0)
  else if KV = GDK_KEY_Tab then
    Controller.Key(akTab, 0)
  else if KV = GDK_KEY_Escape then
    Controller.Key(akEscape, 0)
  else if (KV = GDK_KEY_Return) or (KV = GDK_KEY_KP_Enter) then
    Controller.Key(akReturn, 0)
  else if (KV >= $30) and (KV <= $39) then
    Controller.Key(akDigit, KV - $30)
  else if ((KV >= $41) and (KV <= $5A)) or ((KV >= $61) and (KV <= $7A)) then
  begin
    Ch := Char(KV);
    Controller.Key(akLetter, Ord(Ch));
  end
  else
    Exit(False);
  AfterInput;
end;

function BuildPopup: PGtkWidget;
var
  Menu, Item: PGtkWidget;
begin
  { No menu bar on the frame. Right-click opens this. }
  Menu := gtk_menu_new;
  Item := gtk_menu_item_new_with_label('About Alarm Clock');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnAbout), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Use System Time');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnReset), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_separator_menu_item_new;
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Quit');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnQuit), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  gtk_widget_show_all(Menu);
  Result := Menu;
end;

procedure HostRun;
var
  SW, SH, WinW, WinH: Integer;
begin
  gtk_init(@argc, @argv);
  Controller := TAlarmController.Create(1, AlarmSettingsFile);
  Pix := nil;
  CrossCursor := gdk_cursor_new(GDK_CROSSHAIR);
  PopupMenu := BuildPopup;

  MainWin := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(PGtkWindow(MainWin), 'Alarm Clock');
  gtk_window_set_decorated(PGtkWindow(MainWin), False);
  gtk_window_set_resizable(PGtkWindow(MainWin), False);
  g_signal_connect(G_OBJECT(MainWin), 'delete-event', TGCallback(@OnDelete), nil);
  g_signal_connect(G_OBJECT(MainWin), 'key-press-event', TGCallback(@OnKey), nil);

  DrawArea := gtk_drawing_area_new;
  WinW := Controller.ContentWidth;
  WinH := Controller.ContentHeight;
  gtk_widget_set_size_request(DrawArea, WinW, WinH);
  gtk_container_add(PGtkContainer(MainWin), DrawArea);
  gtk_widget_add_events(DrawArea, GDK_BUTTON_PRESS_MASK or GDK_POINTER_MOTION_MASK);
  { Keys are handled on the toplevel window, so the drawing area does not
    need GTK_CAN_FOCUS. That flag's Pascal binding differs between FPC builds. }
  g_signal_connect(G_OBJECT(DrawArea), 'expose-event', TGCallback(@OnExpose), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'button-press-event', TGCallback(@OnButtonPress), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'motion-notify-event', TGCallback(@OnMotion), nil);

  SW := gdk_screen_width;
  SH := gdk_screen_height;
  gtk_window_move(PGtkWindow(MainWin), SW - WinW - 24, 32);

  g_timeout_add(TickMs, TGSourceFunc(@OnTick), nil);
  Present;
  gtk_widget_show_all(MainWin);
  gtk_widget_grab_focus(DrawArea);
  gtk_main;
  DestroyPix;
  if CrossCursor <> nil then
    gdk_cursor_unref(CrossCursor);
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
