#!/bin/bash
#
#
# Read a single char from /dev/tty, prompting with "$*"
# Note: pressing enter will return a null string. Perhaps a version terminated with X and then remove it in caller?
# See https://unix.stackexchange.com/a/367880/143394 for dealing with multi-byte, etc.
function get_keypress {
  local REPLY IFS=
  >/dev/tty printf '%s' "$*"
  [[ $ZSH_VERSION ]] && read -rk1  # Use -u0 to read from STDIN
  # See https://unix.stackexchange.com/q/383197/143394 regarding '\n' -> ''
  [[ $BASH_VERSION ]] && </dev/tty read -rn1
  printf '%s' "$REPLY"
}
# Get a y/n from the user, return yes=0, no=1 enter=$2
# Prompt using $1.
# If set, return $2 on pressing enter, useful for cancel or defualting
function get_yes_keypress {
  local prompt="${1:-Are you sure}"
  local enter_return=$2
  local REPLY
  # [[ ! $prompt ]] && prompt="[y/n]? "
  while REPLY=$(get_keypress "$prompt"); do
    [[ $REPLY ]] && printf '\n' # $REPLY blank if user presses enter
    case "$REPLY" in
      Y|y)  return 0;;
      N|n)  return 1;;
      '')   [[ $enter_return ]] && return "$enter_return"
    esac
  done
}

# Prompt to confirm, defaulting to YES on <enter>
function confirm_yes {
  local prompt="${*:-Are you sure} [Y/n]? "
  get_yes_keypress "$prompt" 0
}

# by default we'll assume its an archive we don't care about
# but -a should indicate maybe just the audio needs fixing
audio=0

if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
  fpath="`xclip -out`"
elif [ $# -eq 2 ]; then
  if [ $1 == "-a" ]; then
    audio=1
  else
    echo "The only option is -a, I couldn't parse your input."
  fi
  fpath="$2"
else
  fpath="$1"
fi
prestrip=$(echo $fpath| grep "file://");
if [ $? -eq 0 ]; then
  fpath=$(echo $fpath|cut -d":" -f2|cut -b3-);
fi
checkimage="`echo $fpath|grep $PHOTOLIB`"
if [ $? -eq 0 ]; then
  isimage=1
else
  isimage=0
fi
if [ $isimage -ne 0 ]; then
  apath=$HOME/$TARGET/$VIDLIB/$PHOTOLIB/archive
else
  checktarget=`echo $fpath|grep $TARGET`
  if [ $? -ne 0 ]; then
    fpath=$(echo $fpath|sed -e "s/local/$(whoami)\/$TARGET\/$VIDLIB/g");
    apath=$(echo $apath|sed -e "s/local/$(whoami)\/$TARGET\/$VIDLIB/g");
  fi
  ispno=$(echo "$fpath"|grep pno);
  if [ $? -eq 0 ]; then 
    apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/pno-video/archive"
  else
    apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/ARCHIVE"
  fi
fi
if [ $audio -eq 1 ]; then
  apath=$apath/audio
fi 
echo "Archiving $fpath"
confirm_yes "Do you want to proceed? "
mounted=$(mountpoint $HOME/$TARGET);
if [ $? -ne 0 ]; then
  $(sshfs $TARGET:/ $HOME/$TARGET)
fi
cp "$fpath" "$apath"
if [ $? -eq 0 ]; then
  rm -f "$fpath"
  echo "Archived to $apath... syncing"
  synced="rsync -rltuv --delete $HOME/$TARGET/$VIDLIB/$PHOTOLIB $HOME/Pictures/"
  if [ $? -eq 0 ]; then
    echo "done"
  else
    echo "something went wrong during sync"
  fi
else
  echo "something went wrong during archive"
fi
