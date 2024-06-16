#!/bin/bash
#
source $HOME/.globals
source $D/util.sh
source $LH/util.sh
source $D/user_prompts.sh
noninteractive=false

HISTORY="$VIDLIB/.archive_history"
HISTORY_TS_FMT="%Y%m%d_%H%M%S"

function record_archive_history() {
  local fepath="${1:-}"
  local apath="${2:-}"
  local ts=$(date +$HISTORY_TS_FMT)
  local hash=$(shasum -a 256 < "${filepath}")
  local filename=$(basename "${filepath}")
  args=( 
    "${ts}"  
    "${fpath}" 
    "->" 
    "${apath}"
    "${hash}"
  )
  printf -v entry "%s\t" "${args[@]}"
  echo "${entry}" >> "$HISTORY"
}

function undo_archive() {
  reverse_fpath=$(tail -n 1 "${HISTORY}" |awk '{print$2}')
  reverse_apath=$(tail -n 1 "${HISTORY}" |awk '{print$4}')
  bn=$(basename "${reverse_fpath}")
  apath=$(dirname "${reverse_fpath}")
  fpath="${reverse_apath}/${bn}"
  echo "Undoing Archiving of $reverse_fpath to $reverse_apath"
  echo "    by copying $fpath to $apath"
  if ! $noninteractive; then 
    if ! timed_confirm_no "Do you want to proceed? (y/N)"; then
      exit 1
    fi
  fi
  record_archive_history "${fpath}" "${apath}"
  cp -r "${fpath}" "${apath}"
}


if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
  dpath="`xclip -out`"
  if [ $? -eq 0 ]; then
    se "Using $dpath found on the clipboard..."
  else
    >2 printf "No filename provided and nothing on the clipboard.  Exiting."
    exit 1;
  fi
elif [ $# -eq 2 ]; then
  if [[ $1 == "-y" ]]; then
    noninteractive=true
  elif [[ $1 == "-u" ]]; then 
    undo_archive
    exit $?
  else
    se "The only option is -y, I couldn't parse your input."
  fi
  dpath="$2"
else
  dpath="$1"
fi
# echo "is there quotes? $fpath"
#fpath="$(echo \"$fpath\"|xargs|awk '{"$1"="$1"};1')"
# prestrip="$(echo $fpath| grep 'file://')";
# if [ $? -eq 0 ]; then
#   fpath="$(echo $fpath|cut -d':' -f2|cut -b3-)"
# fi
oldfpath="${dpath}"
fpath=$(sanitize_fpath "${dpath}")
se "sanitized fpath: ${fpath}"
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
  apath="$HOME/$TARGET/$VIDLIB/$PHOTOLIB/archive"
elif [ $ismusic -ne 0 ]; then
  ctr=1
  IFS=$'\n' 
  for pathel in $(echo $fpath|tr "/" "\n"); do
    if string_contains "Music" $pathel; then
      # this is the heirarchy if its a single song
      base=ctr
      ((artist_idx=ctr+1))
      ((album_idx=ctr+2))
      ((song_idx=ctr+3))
    fi
    if string_contains ".mp3" "$pathel"; then
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
  if string_contains "local" "$oldfpath"; then
    # if string_contains "$VIDLIB" "$fpath"; then
    #   sedstring="s/\/home\/local/\/$VIDLIB/g"
    # else
    #   sedstring="s/local/$(whoami)\/$TARGET\/$VIDLIB/g"
    # fi
    # fpath="$(echo $fpath|sed -e $sedstring)";
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

# the path coming from jq over the wire ends up double quoted
if string_contains '"' $fpath; then 
  sedstring='s/"//g'
  fpath="$(echo $fpath|sed -e $sedstring)"
fi
if ! [ -n "$fpath" ]; then 
se f
  fready=false
else
  if [ -f "${fpath}" ]; then 
    fready=true # probably 
  fi
fi

if ! [ -n "$apath" ]; then
se a 
  aready=false
else
  if [ -d "${apath}" ]; then
    aready=true # maybe
  fi
fi
if ! $fready && ! $aready; then
  echo "Setup failed. Exiting. fpath: $fpath apath: $apath"
  exit 1
fi
echo "Archiving $fpath to $apath"
if ! $noninteractive; then 
  if ! timed_confirm_no "Do you want to proceed? (y/N)"; then
    exit 1
  fi
fi
mounted=$(mountpoint $HOME/$TARGET);
if [ $? -ne 0 ]; then
  $(sshfs $TARGET:/ $HOME/$TARGET)
fi
mkdir -p "$apath"
if ! [ $? -eq 0 ]; then
  >2 printf "Couldnt mkdir -p $apath, exiting."
  exit 1;
fi
record_archive_history "${fpath}" "${apath}"
cp -r "$fpath" "$apath"
if [ $? -eq 0 ]; then
  rm -rf "$fpath"
  se "Archived to $apath... syncing"
  if [ $ismusic -ne 0 ]; then
    sync_music
  else
    synced="$(rsync -rltuv --delete $HOME/$TARGET/$VIDLIB/$PHOTOLIB $HOME/Pictures/);"
    if [ $? -eq 0 ]; then
      : # echo "done"
    else
      se "something went wrong during sync"
    fi
  fi
else
  bn=$(basename "$fpath")
  farked="$apath"/"$bn"
  if [ -f "$farked" ]; then
    >2  printf "$bn was previously archived and exists at $apath. exiting.\n"
    exit 1
  fi
  se "something went wrong during archive"
fi
