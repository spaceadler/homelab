#!/usr/bin/env bash
# kiwix-serve exits when it has no archives, and would restart-loop forever.
if ! compgen -G "$STORAGE_DIR/Media/Kiwix/*.zim" >/dev/null; then
    echo "  Kiwix has no archives yet: put a .zim from https://library.kiwix.org"
    echo "  in $STORAGE_DIR/Media/Kiwix, then re-run ./install.sh."
    exit 10
fi
