#!/bin/sh
# Flameshot's own "copy file path after save" is lost on Wayland: the
# compositor accepts a clipboard owner only while it has focus, and the
# capture window is already closed by then. wl-copy stays around to own it.
path=$(flameshot gui 2>&1 | sed -n 's/.*Capture saved as //p' | tail -n 1)
if [ -n "$path" ]; then
  printf '%s' "$path" | wl-copy
fi
