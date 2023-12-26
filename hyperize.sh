#!/bin/bash
if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
  fpath="`xclip -out`"
else
  fpath="$1"
fi
mv "$fpath" "$HOME/$TARGET/$VIDLIB/$VIDLIB/pno-video/music/hyperish/"