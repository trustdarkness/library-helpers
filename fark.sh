#!/bin/bash
#

if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
  fpath="`xclip -out`"
  if [ $? -eq 0 ]; then
    echo "Using $fpath found on the clipboard..."
  else
    >&2 printf "No filename provided and nothing on the clipboard.  Exiting."
    exit 1;
  fi
elif [ $# -eq 2 ]; then
  if [ $1 == "-y" ]; then
    noninteractive=1
  else
    echo "The only option is -y, I couldn't parse your input."
  fi
  fpath="$2"
else
  fpath="$1"
fi
 
fpath="$(echo \"$fpath\"|xargs|awk '{$1=$1};1')"
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
checkmusic="$(echo $fpath|grep $MUSICLIB);"
if [ $? -eq 0 ]; then
  ismusic=1
else
  ismusic=0
fi
if [ $isimage -ne 0 ]; then
  apath=$HOME/$TARGET/$VIDLIB/$PHOTOLIB/archive
elif [ $ismusic -ne 0 ]; then
  ctr=1
  IFS=$'\n' 
  for pathel in $(echo $fpath|tr "/" "\n"); do
    if stringContains "Music" $pathel; then
      # this is the heirarchy if its a single song
      base=ctr
      ((artist_idx=ctr+1))
      ((album_idx=ctr+2))
      ((song_idx=ctr+3))
    fi
    if stringContains ".mp3" "$pathel"; then
      # we assume this is the song itself
      songname="$pathel"
    fi
    if [[ $ctr -eq $artist_idx && -z "${songname+x}" ]]; then 
      artistname="$pathel"
    elif [[ $ctr -eq $album_idx && -z "${songname+x}" ]]; then
      albumname="$pathel"
    fi
    lastpathel=$pathel
    ((ctr=$ctr+1))
  done
  apath=$MARCH
  if ! [ -z "${artistname+x}" ]; then
    if [ -z "${albumname+x}" ]; then
      # skipping the negation and reassigning here mostly for readability
      apath=$MARCH
    else
      apath=$apath"/"$artistname
    fi
  fi
  if ! [ -z "${albumname+x}" ]; then
    if ! [ -z "${songname+x}" ]; then
      apath=$apath"/"$albumname
    fi
  fi 

else
  checktarget=`echo $fpath|grep local`
  if stringContains "local" "$fpath"; then
    fpath="$(echo $fpath|sed -e \"s/local/$(whoami)\/$TARGET\/$VIDLIB/g\")";
    apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/ARCHIVE/"
  else
    ispno=$(echo "$fpath"|grep pno);
    if [ $? -eq 0 ]; then 
      apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/pno-video/archive"
    else
      apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/ARCHIVE"
    fi
  fi
fi

echo "Archiving $fpath to $apath"
if [ -z ${noninteractive+x } ]; then 
  confirm_yes "Do you want to proceed? "
fi
mounted=$(mountpoint $HOME/$TARGET);
if [ $? -ne 0 ]; then
  $(sshfs $TARGET:/ $HOME/$TARGET)
fi
mkdir -p "$apath"
if ! [ $? -eq 0 ]; then
  >&2 printf "Couldnt mkdir -p $apath, exiting."
  exit 1;
fi
cp -r "$fpath" "$apath"
if [ $? -eq 0 ]; then
  rm -rf "$fpath"
  echo "Archived to $apath... syncing"
  if [ $ismusic -ne 0 ]; then
    sync_music
  else
    synced="$(rsync -rltuv --delete $HOME/$TARGET/$VIDLIB/$PHOTOLIB $HOME/Pictures/);"
    if [ $? -eq 0 ]; then
      echo "done"
    else
      echo "something went wrong during sync"
    fi
  fi
else
  bn=$(basename "$fpath")
  farked="$apath"/"$bn"
  if [ -f "$farked" ]; then
    >&2  printf "$bn was previously archived and exists at $apath. exiting.\n"
    exit 1
  fi
  echo "something went wrong during archive"
fi
if ! [ -z ${noninteractive+x } ]; then 
  sleep 5
fi
