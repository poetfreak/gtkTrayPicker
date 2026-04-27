#!/bin/bash

set -e

VERSION="1.0.3"
ARCH="amd64"
COMMON_DEPENDS="libgtk-3-0, libnotify-bin, xdg-utils, libayatana-appindicator3-1"

build_package() {
    local package_name="$1"
    local binary_name="$2"
    local desktop_name="$3"
    local desktop_exec="$4"
    local extra_depends="$5"
    local fbc_define="$6"
    local package_dir="${package_name}_${VERSION}_${ARCH}"
    local output_name="$7"

    echo "Compiling ${binary_name}..."
    if [ -n "$fbc_define" ]; then
        fbc -d "$fbc_define" -s gui -exx -g traypicker.bas -x "$binary_name" > "build-${binary_name}.log"
    else
        fbc -s gui -exx -g traypicker.bas -x "$binary_name" > "build-${binary_name}.log"
    fi
    chmod 755 "$binary_name"

    rm -f "build-${binary_name}.log"
    echo -e "\033[32mSuccess!\033[0m ${binary_name} built"

    echo "Creating package structure for ${package_name}..."
    rm -rf "$package_dir"
    mkdir -p "$package_dir/usr/local/bin"
    mkdir -p "$package_dir/usr/share/applications"
    mkdir -p "$package_dir/usr/share/icons/hicolor/scalable/apps"
    mkdir -p "$package_dir/usr/share/icons/gnome/48x48/apps"
    mkdir -p "$package_dir/usr/docs/$package_name"
    mkdir -p "$package_dir/DEBIAN"

    echo "Copying files for ${package_name}..."
    cp "$binary_name" "$package_dir/usr/local/bin/"
    chmod 755 "$package_dir/usr/local/bin/$binary_name"
    cp colorpicker.bas "$package_dir/usr/docs/$package_name/"
    cp makedeb.sh "$package_dir/usr/docs/$package_name/"
    cp README.md "$package_dir/usr/docs/$package_name/"

    if [ -f "traypicker.svg" ]; then
        cp traypicker.svg "$package_dir/usr/share/icons/hicolor/scalable/apps/traypicker.svg"
    fi

    if [ -f "traypicker.png" ]; then
        cp traypicker.png "$package_dir/usr/share/icons/gnome/48x48/apps/traypicker.png"
    else
        echo -e "\033[33mWarning\033[0m: traypicker.png not found."
    fi

    cat > "$package_dir/DEBIAN/control" <<EOF
Package: $package_name
Version: $VERSION
Section: graphics
Priority: optional
Architecture: $ARCH
Depends: $COMMON_DEPENDS, $extra_depends
Maintainer: Eric Sebasta <allpraise@gmail.com>
Description: A simple color picker for the system tray
 A simple color picker for the system tray with color history and clipboard integration.
 Created in FreeBasic by Eric Sebasta.
EOF

    cat > "$package_dir/usr/share/applications/${package_name}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$desktop_name
Comment=Pick colors from the screen
Exec=$desktop_exec
Icon=traypicker
Categories=Graphics;
Terminal=false
EOF

    echo "Building ${output_name}..."
    dpkg-deb --root-owner-group --build "$package_dir" "$output_name"
    rm -rf "$package_dir"
    echo -e "\033[32mSuccess!\033[0m Package created: ${output_name}"
}

build_package \
    "traypicker" \
    "traypicker" \
    "Traypicker" \
    "env GDK_BACKEND=x11 /usr/local/bin/traypicker" \
    "libx11-6, xclip" \
    "" \
    "traypicker_${VERSION}_${ARCH}.deb"

build_package \
    "traypicker-wayland" \
    "traypicker-wayland" \
    "Traypicker (Wayland)" \
    "/usr/local/bin/traypicker-wayland" \
    "wl-clipboard" \
    "TRAYPICKER_FORCE_WAYLAND" \
    "traypicker-wayland_${VERSION}_${ARCH}.deb"
