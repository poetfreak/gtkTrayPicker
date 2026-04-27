'---------------------------------------------------------------
'  traypicker ==     GTK3 color picker for X11 or Wayland     - 
'---------------------------------------------------------------
'  Created in FreeBASIC By Eric Sebasta <allpraise@gmail.com> -
'  Please donate if you find this useful. I'm passionate about
'  making quality apps, and sleeping indoors.
'===============================================================

' NOTE: requires xclip for X11 support. On Wayland, wl-clipboard is used if available, 
' but fallback to xclip if not. If neither is available, the app will still run but 
' clipboard functionality will be disabled.

' REQUIREMENTS:
'  - GTK3 development libraries
'  - libayatana-appindicator3 development libraries
'  - X11 development libraries (for X11 color picking)
'  - xclip (for X11 clipboard support)
'  - wl-clipboard (optional, for Wayland clipboard support)
' Get your development packages and tools set up with:
' sudo apt-get install libgtk-3-dev libayatana-appindicator3-dev libx11-dev \
' xclip wl-clipboard
' Current X11 package output from makedeb.sh:
' traypicker_1.0.3_amd64.deb
' Current Wayland package output from makedeb.sh:
' traypicker-wayland_1.0.3_amd64.deb


#lang "fb" 'ALWAYS!
#Include Once "X11/Xlib.bi"
#Include Once "X11/Xutil.bi"
#Include Once "X11/cursorfont.bi"
#Include Once "gtk/gtk3.bi"
#Include Once "app-indicator.bi"


#inclib "X11"
#inclib "gtk-3"
#inclib "gio-2.0"
#inclib "ayatana-appindicator3"

' NOTE: libayatana-appindicator3 emits a deprecation warning recommending
' libayatana-appindicator-glib for newly written code. On Debian stable
' system, the GTK3 Ayatana dev package is available, but a corresponding
' libayatana-appindicator-glib development target is not currently exposed via
' apt/pkg-config. Keep using this library here until stable ships the GLib
' variant with headers/libs we can link from FreeBASIC.


' --- Data Structures ---

Type ColorInfo
    r As UByte
    g As UByte
    b As UByte
    hex As String * 8 ' #RRGGBB + null
    rgb As String * 17 ' RGB(255,255,255) + null
End Type

Type MotifWmHints ' For disabling window decorations on the preview window
    flags As ULong
    functions As ULong
    decorations As ULong
    inputMode As Long
    status As ULong
End Type

Const MAX_HISTORY = 12
Const PREVIEW_SIZE = 30
Const PREVIEW_BORDER = 2
Const PREVIEW_OFFSET = 24
Dim Shared As ColorInfo history(MAX_HISTORY - 1)
Dim Shared As Integer historyCount = 0
Dim Shared As Integer historyHead = -1 ' Points to the last added color

Dim Shared As Display Ptr dpy
Dim Shared As AppIndicator Ptr trayIcon
Dim Shared As GtkWidget Ptr trayMenu
Dim Shared As GtkWidget Ptr pickColorMenuItem
Dim Shared As Boolean isFirstRun = True
Dim Shared As Boolean isWayland = False
Dim Shared As String clipboard_cmd
Dim Shared As GDBusConnection Ptr waylandConn = NULL
Dim Shared As guint waylandPortalSubscription = 0

Const ABOUT_INDEX = -1
Const PICK_COLOR_INDEX = -2
Const QUIT_INDEX = -3

' --- Forward Declarations ---

Declare Sub on_menu_item_click (ByVal menuItem As GtkMenuItem Ptr, ByVal userData As gpointer)
Declare Function on_menu_item_button_press (ByVal widget As GtkWidget Ptr, ByVal event As GdkEventButton Ptr, ByVal userData As gpointer) As gboolean
Declare Sub copy_and_notify(hexColor As String, rgbColor As String)
Declare Sub copy_rgb_and_notify(hexColor As String, rgbColor As String)
Declare Sub add_to_history(r As UByte, g As UByte, b As UByte, ByVal doSave As Boolean = True)
Declare Sub promote_history_to_top(index As Integer, ByVal doSave As Boolean = True)
Declare Sub save_config()
Declare Sub load_config()
Declare Sub pick_color()
Declare Function command_exists(ByVal cmd As String) As Boolean
Declare Function create_color_icon(r As UByte, g As UByte, b As UByte) As GtkWidget Ptr
Declare Function build_tray_menu() As GtkWidget Ptr
Declare Function sample_screen_color(root As Window, x As Integer, y As Integer, ByRef r As UByte, ByRef g As UByte, ByRef b As UByte) As Boolean
Declare Sub update_preview_window(previewWin As Window, x As Integer, y As Integer, r As UByte, g As UByte, b As UByte)
Declare Sub disable_window_decorations(win As Window)
Declare Sub refresh_tray_menu()
Declare Sub pick_color_wayland()
Declare Sub filtered_glib_log_handler Cdecl (ByVal log_domain As Const gchar Ptr, ByVal log_level As GLogLevelFlags, ByVal message As Const gchar Ptr, ByVal user_data As gpointer)
Declare Sub on_portal_response Cdecl (ByVal conn As GDBusConnection Ptr, ByVal sender_name As Const ZString Ptr, ByVal object_path As Const ZString Ptr, ByVal interface_name As Const ZString Ptr, ByVal signal_name As Const ZString Ptr, ByVal parameters As GVariant Ptr, ByVal user_data As gpointer)
Declare Sub show_message(ByVal msg As String, ByVal isFatal As Boolean = False)

' --- Main Application ---

Sub main()
    g_log_set_default_handler(@filtered_glib_log_handler, NULL)
    gtk_init(NULL, NULL)

    clipboard_cmd = "xclip -selection clipboard"

    #ifdef TRAYPICKER_FORCE_WAYLAND
        isWayland = True
    #else
        If Environ("WAYLAND_DISPLAY") <> "" Then
            isWayland = True
        End If
    #endif

    If isWayland Then
        If command_exists("wl-copy") Then
            clipboard_cmd = "wl-copy"
        End If
    Else
        If Not command_exists("xclip") Then
            show_message("Error: xclip is required for X11 support.", True)
        End If
    End If

    dpy = XOpenDisplay(0)
    If dpy = 0 AndAlso isWayland = False Then
        show_message("Error: Could not open X display. Exiting.", True)
    End If

    trayIcon = app_indicator_new("com.er1c.traypicker", "gtk-color-picker", APP_INDICATOR_CATEGORY_APPLICATION_STATUS)
    If trayIcon = 0 Then
        show_message("Error: Could not create AppIndicator.", True)
    End If

    app_indicator_set_status(trayIcon, APP_INDICATOR_STATUS_ACTIVE)

    load_config()
    refresh_tray_menu()

    gtk_main()

    If waylandPortalSubscription <> 0 AndAlso waylandConn <> NULL Then
        g_dbus_connection_signal_unsubscribe(waylandConn, waylandPortalSubscription)
    End If
    If waylandConn <> NULL Then
        g_object_unref(waylandConn)
    End If
    If dpy <> 0 Then XCloseDisplay(dpy)
End Sub

main()

'=======>>==>>==>> Signal Handlers & Logic <<==<<==<<======================<<<<

Sub filtered_glib_log_handler Cdecl (ByVal log_domain As Const gchar Ptr, ByVal log_level As GLogLevelFlags, ByVal message As Const gchar Ptr, ByVal user_data As gpointer)
    If message <> NULL Then
        Dim As String msg = *Cast(Const ZString Ptr, message)
        If InStr(msg, "libayatana-appindicator is deprecated. Please use libayatana-appindicator-glib in newly written code.") > 0 Then
            Return
        End If
    End If

    g_log_default_handler(log_domain, log_level, message, user_data)
End Sub

Sub show_message(ByVal msg As String, ByVal isFatal As Boolean = False)
    Dim As GtkWidget Ptr dialog = gtk_message_dialog_new(NULL, _
                                     GTK_DIALOG_MODAL, _
                                     GTK_MESSAGE_ERROR, _
                                     GTK_BUTTONS_OK, _
                                     "%s", msg)
    gtk_window_set_title(GTK_WINDOW(dialog), "Traypicker Error")
    gtk_dialog_run(GTK_DIALOG(dialog))
    gtk_widget_destroy(dialog)
    
    If isFatal Then End 1
End Sub

Sub promote_history_to_top(index As Integer, ByVal doSave As Boolean = True)
    If index < 0 OrElse index >= MAX_HISTORY Then Return
    If historyCount <= 0 OrElse historyHead < 0 Then Return
    If index = historyHead Then
        If doSave Then save_config()
        Return
    End If

    Dim As Integer distance = -1
    For i As Integer = 0 To historyCount - 1
        Dim As Integer currentIndex = (historyHead - i + MAX_HISTORY) Mod MAX_HISTORY
        If currentIndex = index Then
            distance = i
            Exit For
        End If
    Next i

    If distance < 0 Then Return

    Dim As ColorInfo temp = history(index)
    For j As Integer = distance To 1 Step -1
        Dim As Integer destIdx = (historyHead - j + MAX_HISTORY) Mod MAX_HISTORY
        Dim As Integer srcIdx = (historyHead - j + 1 + MAX_HISTORY) Mod MAX_HISTORY
        history(destIdx) = history(srcIdx)
    Next j
    history(historyHead) = temp

    If doSave Then save_config()
End Sub

Sub add_to_history(r As UByte, g As UByte, b As UByte, ByVal doSave As Boolean = True)
    Dim As String newHex = "#" & Hex(r, 2) & Hex(g, 2) & Hex(b, 2)

    ' Check if color already exists in history
    If historyCount > 0 Then
        For i As Integer = 0 To historyCount - 1
            Dim As Integer index = (historyHead - i + MAX_HISTORY) Mod MAX_HISTORY
            If history(index).hex = newHex Then
                promote_history_to_top(index, doSave)
                Return
            End If
        Next i
    End If

    ' Color not in history - add it as new
    historyHead = (historyHead + 1) Mod MAX_HISTORY

    history(historyHead).r = r
    history(historyHead).g = g
    history(historyHead).b = b
    history(historyHead).hex = newHex
    history(historyHead).rgb = "RGB(" & r & "," & g & "," & b & ")"

    If historyCount < MAX_HISTORY Then
        historyCount += 1
    End If

    If doSave Then save_config()
End Sub

Sub refresh_tray_menu()
    If trayMenu <> 0 Then
        gtk_widget_destroy(trayMenu)
    End If

    trayMenu = build_tray_menu()
    app_indicator_set_menu(trayIcon, GTK_MENU(trayMenu))

    If pickColorMenuItem <> 0 Then
        app_indicator_set_secondary_activate_target(trayIcon, pickColorMenuItem)
    End If
End Sub

Sub save_config()
    Dim As String configFile = Environ("HOME") & "/.config/.colorpicker.ini"
    Dim As Integer f = FreeFile
    If Open(configFile For Output As #f) = 0 Then
        '== Iterate from oldest to newest so loading preserves order ==
        If historyCount > 0 Then
            For i As Integer = historyCount - 1 To 0 Step -1
                Dim As Integer index = (historyHead - i + MAX_HISTORY) Mod MAX_HISTORY
                Print #f, history(index).hex
            Next
        End If
        Close #f
    End If
End Sub

Sub load_config()
    Dim As String configFile = Environ("HOME") & "/.config/.colorpicker.ini"
    Dim As Integer f = FreeFile
    If Open(configFile For Input As #f) = 0 Then
        Dim As String lineBuf
        While Not Eof(f)
            Line Input #f, lineBuf
            lineBuf = Trim(lineBuf)
            If Len(lineBuf) = 7 And Left(lineBuf, 1) = "#" Then
                Dim As UByte r = ValInt("&H" & Mid(lineBuf, 2, 2))
                Dim As UByte g = ValInt("&H" & Mid(lineBuf, 4, 2))
                Dim As UByte b = ValInt("&H" & Mid(lineBuf, 6, 2))
                add_to_history(r, g, b, False) ' False = don't save while loading
            End If
        Wend
        Close #f
    End If
End Sub

Sub copy_and_notify(hexColor As String, rgbColor As String)
    ' Copy hex to clipboard
    Shell("printf '" & hexColor & "' | " & clipboard_cmd)

    ' Notify with both
    Shell("notify-send 'Color in clipboard' '" & hexColor & "  (" & rgbColor & ")'")
End Sub

Sub copy_rgb_and_notify(hexColor As String, rgbColor As String)
    ' Copy rgb to clipboard
    Shell("printf '" & rgbColor & "' | " & clipboard_cmd)

    ' Notify with both
    Shell("notify-send 'RGB Color in clipboard' '" & rgbColor & "'")
End Sub

Function command_exists(ByVal cmd As String) As Boolean
    Return (Shell("command -v " & cmd & " > /dev/null 2>&1") = 0)
End Function

Function create_color_icon(r As UByte, g As UByte, b As UByte) As GtkWidget Ptr
    ' Create the color swatch image
    Dim As GdkPixbuf Ptr pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 24, 24)
    Dim As UInteger pixel = (CUInt(r) Shl 24) Or (CUInt(g) Shl 16) Or (CUInt(b) Shl 8) Or &HFF
    gdk_pixbuf_fill(pixbuf, pixel)
    Dim As GtkWidget Ptr image = gtk_image_new_from_pixbuf(pixbuf)
    g_object_unref(pixbuf)

    ' Create a frame to act as a border
    Dim As GtkWidget Ptr frame = gtk_frame_new(NULL)
    gtk_frame_set_shadow_type(GTK_FRAME(frame), GTK_SHADOW_IN)
    gtk_container_add(GTK_CONTAINER(frame), image)
    Return frame
End Function

Function sample_screen_color(root As Window, x As Integer, y As Integer, ByRef r As UByte, ByRef g As UByte, ByRef b As UByte) As Boolean
    Dim As XImage Ptr img = XGetImage(dpy, root, x, y, 1, 1, AllPlanes, ZPixmap)
    If img = 0 Then Return FALSE

    Dim As UInteger pixel = img->f.get_pixel(img, 0, 0)
    r = (pixel Shr 16) And &HFF
    g = (pixel Shr 8) And &HFF
    b = pixel And &HFF

    XDestroyImage(img)
    Return TRUE
End Function

Sub update_preview_window(previewWin As Window, x As Integer, y As Integer, r As UByte, g As UByte, b As UByte)
    Dim As Integer screenNum = DefaultScreen(dpy)
    Dim As Integer screenWidth = DisplayWidth(dpy, screenNum)
    Dim As Integer screenHeight = DisplayHeight(dpy, screenNum)
    Dim As Integer previewX = x + PREVIEW_OFFSET
    Dim As Integer previewY = y + PREVIEW_OFFSET

    If previewX + PREVIEW_SIZE > screenWidth Then
        previewX = x - PREVIEW_SIZE - PREVIEW_OFFSET
    End If
    If previewY + PREVIEW_SIZE > screenHeight Then
        previewY = y - PREVIEW_SIZE - PREVIEW_OFFSET
    End If
    If previewX < 0 Then previewX = 0
    If previewY < 0 Then previewY = 0

    Dim As ULong pixelColor = (CULng(r) Shl 16) Or (CULng(g) Shl 8) Or CULng(b)
    XSetWindowBackground(dpy, previewWin, pixelColor)
    XMoveResizeWindow(dpy, previewWin, previewX, previewY, PREVIEW_SIZE, PREVIEW_SIZE)
    XClearWindow(dpy, previewWin)
    XMapRaised(dpy, previewWin)
    XRaiseWindow(dpy, previewWin)
    XSync(dpy, FALSE)
End Sub

Sub disable_window_decorations(win As Window)
    Dim As ULong motifHintsAtom = XInternAtom(dpy, "_MOTIF_WM_HINTS", FALSE)
    If motifHintsAtom = 0 Then Return

    Dim As MotifWmHints hints
    hints.flags = 2
    hints.functions = 0
    hints.decorations = 0
    hints.inputMode = 0
    hints.status = 0

    XChangeProperty(dpy, win, motifHintsAtom, motifHintsAtom, 32, PropModeReplace, Cast(UByte Ptr, @hints), 5)
End Sub

Sub pick_color()
    If isWayland Then
        pick_color_wayland()
        Return
    End If

    ' If we get here, isWayland is false, so dpy should be valid.
    If dpy = 0 Then
        Return ' Should not happen due to startup check
    End If

    Dim As Window root = XDefaultRootWindow(dpy)
    Dim As Cursor pickCursor = XCreateFontCursor(dpy, XC_crosshair)
    Dim As Integer screenNum = DefaultScreen(dpy)
    Dim As Window previewWin = XCreateSimpleWindow(dpy, root, 0, 0, PREVIEW_SIZE, PREVIEW_SIZE, PREVIEW_BORDER, _
        BlackPixel(dpy, screenNum), WhitePixel(dpy, screenNum))
    disable_window_decorations(previewWin)

    ' Short delay to allow the tray icon click to release any grabs
    Sleep 100, 1

    ' Grab the mouse with a crosshair cursor
    Dim As Integer grabResult = XGrabPointer(dpy, root, 0, ButtonPressMask Or ButtonReleaseMask Or PointerMotionMask, _
        GrabModeAsync, GrabModeAsync, None, pickCursor, CurrentTime)
    If grabResult <> GrabSuccess Then
        XDestroyWindow(dpy, previewWin)
        XFreeCursor(dpy, pickCursor)
        Return
    End If

    Dim As Window rootReturn, childReturn
    Dim As Long rootX, rootY, winX, winY
    Dim As Long maskReturn
    Dim As UByte previewR = 255, previewG = 255, previewB = 255

    If XQueryPointer(dpy, root, @rootReturn, @childReturn, @rootX, @rootY, @winX, @winY, @maskReturn) <> 0 Then
        If sample_screen_color(root, rootX, rootY, previewR, previewG, previewB) Then
            update_preview_window(previewWin, rootX, rootY, previewR, previewG, previewB)
        End If
    End If

    XFlush(dpy) ' Ensure the grab request is sent immediately

    Dim As XEvent ev
    Dim As Boolean colorPicked = False

    ' nested loop to capture click
    While True
        XNextEvent(dpy, @ev)
        If ev.type = ButtonPress Then
            Dim As XButtonEvent Ptr bev = Cast(XButtonEvent Ptr, @ev)
            If bev->button = Button1 Then

                ' Read pixel under cursor
                Dim As UByte r, g, b
                If sample_screen_color(root, bev->x_root, bev->y_root, r, g, b) Then
                    ' Add to history
                    add_to_history(r, g, b)

                    ' Copy and notify
                    copy_and_notify(history(historyHead).hex, history(historyHead).rgb)
                End If
                
                colorPicked = TRUE
                ' Do not exit yet; wait for ButtonRelease to "eat" the click
            Else
                Exit While
            End If
        ElseIf ev.type = MotionNotify Then
            Dim As XMotionEvent Ptr mev = Cast(XMotionEvent Ptr, @ev)
            Dim As UByte r, g, b
            If sample_screen_color(root, mev->x_root, mev->y_root, r, g, b) Then
                update_preview_window(previewWin, mev->x_root, mev->y_root, r, g, b)
            End If
        ElseIf ev.type = ButtonRelease Then
            Dim As XButtonEvent Ptr bev = Cast(XButtonEvent Ptr, @ev)
            If bev->button = Button1 And colorPicked Then
                Exit While
            End If
        End If
    Wend

    XUngrabPointer(dpy, CurrentTime)
    XUnmapWindow(dpy, previewWin)
    XDestroyWindow(dpy, previewWin)
    XFreeCursor(dpy, pickCursor)
    XFlush(dpy)

    refresh_tray_menu()
End Sub

Function build_tray_menu() As GtkWidget Ptr
    Dim As GtkWidget Ptr menu = gtk_menu_new()

    ' Note: AppIndicator menus do not support Pango markup or custom child widgets.
    ' We must use standard labels for the tray menu to be visible.
    ' Tray stuff in Linux is so stupid right now.
    pickColorMenuItem = gtk_menu_item_new_with_label("PICK COLOR")
    g_signal_connect(pickColorMenuItem, "activate", G_CALLBACK(@on_menu_item_click), Cast(gpointer, PICK_COLOR_INDEX))
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), pickColorMenuItem)

    Dim As GtkWidget Ptr sep0 = gtk_separator_menu_item_new()
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep0)

    Dim As GtkWidget Ptr aboutItem = gtk_menu_item_new_with_label("About")
    g_signal_connect(aboutItem, "activate", G_CALLBACK(@on_menu_item_click), Cast(gpointer, ABOUT_INDEX))
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), aboutItem)

    Dim As GtkWidget Ptr sep1 = gtk_separator_menu_item_new()
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep1)

    If historyCount > 0 Then
        For i As Integer = historyCount - 1 To 0 Step -1
            Dim As Integer index = (historyHead - i + MAX_HISTORY) Mod MAX_HISTORY

            Dim As GtkWidget Ptr menuItem = gtk_menu_item_new()
            Dim As GtkWidget Ptr box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)
            Dim As GtkWidget Ptr icon = create_color_icon(history(index).r, history(index).g, history(index).b)
            Dim As GtkWidget Ptr lbl = gtk_label_new(history(index).hex & "   " & history(index).rgb)

            gtk_container_add(GTK_CONTAINER(box), icon)
            gtk_container_add(GTK_CONTAINER(box), lbl)
            gtk_container_add(GTK_CONTAINER(menuItem), box)

            gtk_widget_set_tooltip_text(menuItem, "Left-click: Copy Hex" & Chr(10) & "Right-click: Copy RGB")

            g_signal_connect(menuItem, "activate", G_CALLBACK(@on_menu_item_click), Cast(gpointer, index))
            g_signal_connect(menuItem, "button-press-event", G_CALLBACK(@on_menu_item_button_press), Cast(gpointer, index))

            gtk_menu_shell_append(GTK_MENU_SHELL(menu), menuItem)
        Next i

        Dim As GtkWidget Ptr separator = gtk_separator_menu_item_new()
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), separator)
    Else
        Dim As GtkWidget Ptr emptyItem = gtk_menu_item_new_with_label("[No Color History]")
        gtk_widget_set_sensitive(emptyItem, FALSE)
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), emptyItem)
    End If

    Dim As GtkWidget Ptr quitItem = gtk_menu_item_new_with_label("Quit")
    g_signal_connect(quitItem, "activate", G_CALLBACK(@on_menu_item_click), Cast(gpointer, QUIT_INDEX))
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), quitItem)

    gtk_widget_show_all(menu)

    Return menu
End Function

Sub on_menu_item_click (ByVal menuItem As GtkMenuItem Ptr, ByVal userData As gpointer)
    Dim As Integer index = Cast(Integer, userData)
    
    If index = PICK_COLOR_INDEX Then
        pick_color()
        Return
    End If

    If index = ABOUT_INDEX Then
        Dim As GtkWidget Ptr dialog = gtk_dialog_new()
        gtk_window_set_title(GTK_WINDOW(dialog), "About Traypicker")
        gtk_window_set_modal(GTK_WINDOW(dialog), TRUE)
        gtk_window_set_resizable(GTK_WINDOW(dialog), TRUE)
        gtk_window_set_default_size(GTK_WINDOW(dialog), 380, -1)
        gtk_dialog_add_button(GTK_DIALOG(dialog), "_Close", GTK_RESPONSE_CLOSE)

        Dim As GtkWidget Ptr content_area = gtk_dialog_get_content_area(GTK_DIALOG(dialog))
        Dim As GtkWidget Ptr vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10)
        gtk_container_set_border_width(GTK_CONTAINER(vbox), 15)

        Dim As GtkWidget Ptr titleLabel = gtk_label_new(NULL)
        gtk_label_set_markup(GTK_LABEL(titleLabel), "<span size='xx-large' font_family='monospace'><b>Traypicker 1.0.3</b></span>")
        gtk_label_set_justify(GTK_LABEL(titleLabel), GTK_JUSTIFY_CENTER)
        gtk_widget_set_halign(titleLabel, GTK_ALIGN_CENTER)

        Dim As GtkWidget Ptr createdLabel = gtk_label_new(NULL)
        gtk_label_set_markup(GTK_LABEL(createdLabel), "<span><big>Created in FreeBasic by Eric Sebasta</big></span>")
        gtk_label_set_justify(GTK_LABEL(createdLabel), GTK_JUSTIFY_CENTER)
        gtk_widget_set_halign(createdLabel, GTK_ALIGN_CENTER)

        Dim As GtkWidget Ptr emailLink = gtk_link_button_new_with_label("mailto:allpraise@gmail.com?subject=Traypicker", "allpraise@gmail.com")
        gtk_widget_set_halign(emailLink, GTK_ALIGN_CENTER)

        Dim As GtkWidget Ptr cashLabel = gtk_label_new(NULL)
        gtk_label_set_markup(GTK_LABEL(cashLabel), "<b><span foreground='#008000'>CASHAPP: $Er1cMIguy</span></b>")
        gtk_label_set_justify(GTK_LABEL(cashLabel), GTK_JUSTIFY_CENTER)
        gtk_widget_set_halign(cashLabel, GTK_ALIGN_CENTER)

        gtk_box_pack_start(GTK_BOX(vbox), titleLabel, FALSE, FALSE, 5)
        gtk_box_pack_start(GTK_BOX(vbox), createdLabel, FALSE, FALSE, 5)
        gtk_box_pack_start(GTK_BOX(vbox), emailLink, FALSE, FALSE, 5)
        gtk_box_pack_start(GTK_BOX(vbox), cashLabel, FALSE, FALSE, 5)

        gtk_container_add(GTK_CONTAINER(content_area), vbox)
        gtk_widget_show_all(dialog)

        gtk_dialog_run(GTK_DIALOG(dialog))
        gtk_widget_destroy(dialog)
        Return
    End If
    
    If index = QUIT_INDEX Then
        Dim As GtkWidget Ptr dialog = gtk_message_dialog_new(NULL, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO, "Are you sure you want to quit?")
        gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_YES)
        Dim As Integer response = gtk_dialog_run(GTK_DIALOG(dialog))
        gtk_widget_destroy(dialog)

        If response = GTK_RESPONSE_YES Then
            gtk_main_quit()
        End If
        Return
    End If

    If index >= 0 AndAlso index < MAX_HISTORY Then
        promote_history_to_top(index)
        copy_and_notify(history(historyHead).hex, history(historyHead).rgb)

        refresh_tray_menu()
    End If
End Sub

Function on_menu_item_button_press (ByVal widget As GtkWidget Ptr, ByVal event As GdkEventButton Ptr, ByVal userData As gpointer) As gboolean
    If event->button = 3 Then ' Right click
        Dim As Integer index = Cast(Integer, userData)
        If index >= 0 AndAlso index < MAX_HISTORY Then
            promote_history_to_top(index)
            copy_rgb_and_notify(history(historyHead).hex, history(historyHead).rgb)

            refresh_tray_menu()

            ' Close the menu
            Dim As GtkWidget Ptr parent = gtk_widget_get_parent(widget)
            If parent <> 0 Then
                gtk_menu_shell_deactivate(Cast(GtkMenuShell Ptr, parent))
            End If
            Return TRUE
        End If
    End If
    Return FALSE
End Function

' --- Wayland Portal Implementation ---

Sub pick_color_wayland()
    Dim As GError Ptr g_err = NULL
    If waylandConn = NULL Then
        waylandConn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, @g_err)
    End If

    If waylandConn = NULL Then
        Shell("notify-send 'Traypicker Error' 'Could not connect to session bus.'")
        If g_err <> NULL Then g_error_free(g_err)
        Return
    End If
    If g_err <> NULL Then g_error_free(g_err)

    ' Generate a unique token for the request
    Dim As String token = "traypicker_" & Int(Timer * 1000000)
    
    ' Prepare sender ID for object path (remove : and replace . with _)
    Dim As ZString Ptr s_ptr = Cast(ZString Ptr, g_dbus_connection_get_unique_name(waylandConn))
    Dim As String sender = *s_ptr
    Dim As String sender_id = Mid(sender, 2) 
    
    For i As Integer = 0 To Len(sender_id) - 1
        If sender_id[i] = Asc(".") Then sender_id[i] = Asc("_")
    Next
    
    Dim As String object_path = "/org/freedesktop/portal/desktop/request/" & sender_id & "/" & token

    If waylandPortalSubscription <> 0 Then
        g_dbus_connection_signal_unsubscribe(waylandConn, waylandPortalSubscription)
        waylandPortalSubscription = 0
    End If

    ' Subscribe to Response signal on the expected request object path
    waylandPortalSubscription = g_dbus_connection_signal_subscribe(waylandConn, _
        "org.freedesktop.portal.Desktop", _
        "org.freedesktop.portal.Request", _
        "Response", _
        object_path, _
        NULL, _
        G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE, _
        @on_portal_response, _
        NULL, _
        NULL)

    ' Build options: { 'handle_token': <token> }
    Dim As GVariantBuilder builder
    Dim As GVariantType Ptr type_asv = g_variant_type_new("a{sv}")
    g_variant_builder_init(@builder, type_asv)
    g_variant_type_free(type_asv)
    
    g_variant_builder_add(@builder, "{sv}", "handle_token", g_variant_new_string(StrPtr(token)))
    Dim As GVariant Ptr options = g_variant_builder_end(@builder)

    ' Call PickColor method
    g_dbus_connection_call(waylandConn, _
        "org.freedesktop.portal.Desktop", _
        "/org/freedesktop/portal/desktop", _
        "org.freedesktop.portal.Screenshot", _
        "PickColor", _
        g_variant_new("(sa{sv})", "", options), _
        NULL, _
        G_DBUS_CALL_FLAGS_NONE, _
        -1, _
        NULL, _
        NULL, _
        NULL)
End Sub

Sub on_portal_response Cdecl (ByVal conn As GDBusConnection Ptr, ByVal sender_name As Const ZString Ptr, ByVal object_path As Const ZString Ptr, ByVal interface_name As Const ZString Ptr, ByVal signal_name As Const ZString Ptr, ByVal parameters As GVariant Ptr, ByVal user_data As gpointer)
    If waylandPortalSubscription <> 0 Then
        g_dbus_connection_signal_unsubscribe(conn, waylandPortalSubscription)
        waylandPortalSubscription = 0
    End If

    Dim As UInteger response_code
    Dim As GVariant Ptr results = NULL
    
    g_variant_get(parameters, "(u@a{sv})", @response_code, @results)
    
    If response_code = 0 AndAlso results <> NULL Then
        Dim As GVariant Ptr color_var = g_variant_lookup_value(results, "color", G_VARIANT_TYPE("(ddd)"))
        If color_var <> NULL Then
            Dim As Double r_dbl, g_dbl, b_dbl
            g_variant_get(color_var, "(ddd)", @r_dbl, @g_dbl, @b_dbl)
            
            Dim As UByte r = CByte(r_dbl * 255)
            Dim As UByte g = CByte(g_dbl * 255)
            Dim As UByte b = CByte(b_dbl * 255)
            
            add_to_history(r, g, b)
            copy_and_notify(history(historyHead).hex, history(historyHead).rgb)
            
            g_variant_unref(color_var)
        End If
    End If
    
    If results <> NULL Then g_variant_unref(results)
End Sub
