# Traypicker

Traypicker is a small GTK3 system tray color picker written in FreeBASIC for Linux desktops.

It supports both X11 and Wayland, keeps a color history, copies picked colors to the clipboard, and lives in the tray instead of staying open as a regular window.

## Features

- System tray app built with GTK3 and Ayatana AppIndicator
- X11 color picking with a live preview square near the cursor
- Wayland color picking through the `xdg-desktop-portal` `PickColor` API
- Clipboard copy for both hex and RGB values
- Persistent color history stored in the user config directory
- Left-click a history item to copy hex
- Right-click a history item to copy RGB

## Project Status

The project currently builds two Debian packages from the same source:

- package name `traypicker`, version `1.0.3`
- package name `traypicker-wayland`, version `1.0.3`

The source file is [`colorpicker.bas`](./colorpicker.bas), and packaging is handled by [`makedeb.sh`](./makedeb.sh).

## Requirements

### Build Requirements

This project assumes `fbc` is already installed.

Install the remaining build dependencies with:

```bash
sudo apt-get install libgtk-3-dev libayatana-appindicator3-dev libx11-dev xclip wl-clipboard
```

Notes:

- `xclip` is required for X11 clipboard support.
- `wl-clipboard` is used on Wayland when available.
- The program links against GTK3, X11, GIO, and Ayatana AppIndicator.

### Runtime Requirements

The generated Debian packages declare runtime dependencies automatically.

In practice:

- X11 package runtime needs `libx11-6` and `xclip`
- Wayland package runtime needs `wl-clipboard`
- Both builds rely on `libgtk-3-0`, `libnotify-bin`, `xdg-utils`, and `libayatana-appindicator3-1`

## Building

### Quick Local Build

For a local binary build:

```bash
./build.sh
```

That script currently builds a binary named `traypicker`.

### Debian Package Build

To build both Debian packages:

```bash
./makedeb.sh
```

This currently writes these files:

- `traypicker_1.0.3_amd64.deb`
- `traypicker-wayland_1.0.3_amd64.deb`

During packaging, the script compiles:

- `traypicker` for X11
- `traypicker-wayland` for Wayland

## Installing the Packages

After building, install either package with `apt`:

```bash
sudo apt install ./traypicker_1.0.3_amd64.deb
```

or:

```bash
sudo apt install ./traypicker-wayland_1.0.3_amd64.deb
```

The package metadata inside those `.deb` files is:

- `traypicker_1.0.3_amd64.deb`
- `traypicker-wayland_1.0.3_amd64.deb`

## Usage

Launch the app from your applications menu or from a terminal.

X11 build:

```bash
traypicker
```

Wayland build:

```bash
traypicker-wayland
```

Once running:

1. Click `PICK COLOR` from the tray menu.
2. Pick a color from the screen.
3. Traypicker copies the hex value to the clipboard and shows a notification.
4. Open the tray menu again to see the saved history.

History behavior:

- Left-click a history item to copy its hex value
- Right-click a history item to copy its RGB value
- Reusing a color moves it to the top instead of creating a duplicate

## Configuration

Traypicker stores history in:

```text
~/.config/.colorpicker.ini
```

The history file contains one hex color per line.

## Backend Notes

### X11

On X11, Traypicker:

- grabs the pointer
- samples pixels directly through `XGetImage`
- shows a small live preview window near the cursor

### Wayland

On Wayland, direct screen pixel access is not used.

Instead, Traypicker calls:

- `org.freedesktop.portal.Desktop`
- interface `org.freedesktop.portal.Screenshot`
- method `PickColor`

That makes the Wayland build much more compatible with modern compositors, but it depends on a working desktop portal implementation.

## Notes About Tray Support

Linux tray behavior varies across desktop environments.

This project uses Ayatana AppIndicator instead of the deprecated `GtkStatusIcon` path because it is a more practical option across modern desktops.

The source includes a note about a future upgrade to the GLib-flavored Ayatana variant when the development package is available in stable Debian repositories.

## Repository Layout

- [`colorpicker.bas`](./colorpicker.bas): main application source
- [`libappindicator/app-indicator.bi`](./libappindicator/app-indicator.bi): FreeBASIC binding used by the project
- [`build.sh`](./build.sh): quick local build script
- [`makedeb.sh`](./makedeb.sh): Debian packaging script
- [`workflow.md`](./workflow.md): project notes and development history

## Troubleshooting

### X11 build exits with an xclip error

Install `xclip`:

```bash
sudo apt-get install xclip
```

### Wayland color picking does not work

Check that:

- you are running the Wayland build
- `wl-clipboard` is installed
- your session has a working `xdg-desktop-portal`

### Tray icon/menu behavior is inconsistent

That is often desktop-environment specific. AppIndicator support can vary depending on the compositor, shell extensions, and installed tray compatibility packages.

## Author

Created in FreeBASIC by Eric Sebasta.

Contact: `allpraise@gmail.com`
