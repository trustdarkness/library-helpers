#!/bin/bash
if [ -z "$VIDLIB" ] || [ -z "$TARGET" ]; then
  >&2 printf "export TARGET and VIDLIB or provide it on the command line.\n"
  exit 1;
fi
mkdir -p $HOME/$VIDLIB
mounted=$(mountpoint $HOME/$VIDLIB);
if [ $? -ne 0 ]; then
  sshfs $TARGET:/$VIDLIB/$VIDLIB $HOME/$VIDLIB
else
	echo "$VIDLIB seems to already be mounted"
fi
