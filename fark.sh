#!/bin/bash
#
source $HOME/.globals
source $D/util.sh
source $LH/util.sh
source $D/user_prompts.sh
fark_noninteractive=false
DEBUG=false

# temporary 2024-11 during data recovery
container="/run/media/mt/BB"
tempvidlib="mmzz"
cache="/CityInFlames"
photoname="fodder"

HISTORY="/$container/$tempvidlib/$VIDLIB/.archive_history"
HISTORY_TS_FMT="%Y%m%d_%H%M%S"

if ! declare -F "tru" > /dev/null 2>&1; then 
  source "$D/existence.sh"
fi

function record_archive_history() {
  local fpath="${1:-}"
  local apath="${2:-}"
  local ts=$(date +$HISTORY_TS_FMT)
  local hash=$(shasum -a 256 < "${fpath}")
  local filename=$(basename "${fpath}")
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
  
  
  if tru $fark_noninteractive; then
    local echo="notify-send fark-undo"
  else 
    local echo="echo"
  fi
  bn=$(basename "${reverse_fpath}")
  apath=$(dirname "${reverse_fpath}")
  fpath="${reverse_apath}/${bn}"
  $echo "Undoing Archiving of $reverse_fpath to $reverse_apath"
  $echo "    by copying $fpath to $apath"
  if untru $fark_noninteractive; then 
    if ! timed_confirm_yes "Do you want to proceed? (Y/n)"; then
      exit 1
    fi
  fi
  
  if cp -r "${fpath}" "${apath}"; then
    sed -i '$ d' "${HISTORY}"
    exit 0
  fi
  exit 1
}

function main() {
  fark_noninteractive=false
  args=("$@")
  # for players that fark is hooked into, try to resume/advance
  # on success (currently only geeqie)
  resume=false
  geeqie=false
  optspec="yugr:d:"
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      y)
        fark_noninteractive=true
        ;;
      u)
        undo_archive
        exit $?
        ;;
      d)
        destination="${OPTARG}"
        ;;
      r)
        resume=true
        player="$OPTARG"
        ;;
      g) 
        geeqie=true
        fark_noninteractive=true
        resume=true
        ;;
      *)
        help
        ;;
    esac
  done
  if $fark_noninteractive; then 
    function p() {
      subject="${1:-}"
      msg="${2:-}"
      if type -p notify-send > /dev/null 2>&1; then 
        notify-send "$subject" "$msg"
      fi
    }
  else
    function p() {
      printf "%15s: %s" "$subject" "$msg"
    }
  fi
  dpath="${@:$OPTIND:1}"
  if [ -z "$dpath" ]; then
    # no filepath supplied, try the clipboard
    dpath="$(xclip -out | xargs)"
    if [ $? -gt 0 ] || [ -z "$dpath" ]; then
      >2 printf "No filename provided and nothing on the clipboard.  Exiting."
      exit 1;
    fi
  fi
  # echo "is there quotes? $fpath"
  #fpath="$(echo \"$fpath\"|xargs|awk '{"$1"="$1"};1')"
  # prestrip="$(echo $fpath| grep 'file://')";
  # if [ $? -eq 0 ]; then
  #   fpath="$(echo $fpath|cut -d':' -f2|cut -b3-)"
  # fi
  oldfpath="${dpath}"
  fpath=$(sanitize_fpath "${dpath}")
  if "$DEBUG"; then 
    se "sanitized fpath: ${fpath}"
  fi
  if ! [ -f "${fpath}" ]; then
    if $geeqie; then 
      fpath=$(geeqie --remote --tell)
    else
      p "could not fark" "no file found at ${fpath}\n invoked as fark ${args[@]}"
      exit 1
    fi
  fi
  echo
  # 2024-11
  echo $fpath|grep $photoname
  if [ $? -eq 0 ]; then
    isimage=true
    geeqie --remote --slideshow-stop
  else
    isimage=false
  fi
  echo $fpath|grep $MUSICLIB
  if [ $? -eq 0 ]; then
    ismusic=true
  else
    ismusic=false
  fi
  if $isimage; then
    # 2024-11
    # apath="$HOME/$TARGET/$VIDLIB/$PHOTOLIB/archive"
    apath="$PHOTOLIB/archive"
  elif $ismusic; then
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
      # 2024-11
      # apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/ARCHIVE/"
      apath="/$container/$tempvidlib/$VIDLIB/ARCHIVE"
    else
      ispno=$(echo "$fpath"|grep pno);
      if [ $? -eq 0 ]; then 
        # 2024-11
        # apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/pno-video/archive"
        apath="/$container/$tempvidlib/$VIDLIB/pno-video/archive"
      else
        # 2024-11
        # apath="$HOME/$TARGET/$VIDLIB/$VIDLIB/ARCHIVE"
        apath="/$container/$tempvidlib/$VIDLIB/ARCHIVE"
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
  if exists "destination" && [ -d "$destination" ]; then
    apath="$destination"
  fi
  if ! $fready && ! $aready; then
    echo "Setup failed. Exiting. fpath: $fpath apath: $apath"
    exit 1
  fi

  
  if ! $fark_noninteractive; then 
    echo "Archiving $fpath to $apath"
    if ! timed_confirm_yes "Do you want to proceed? (Y/n) "; then
      exit 1
    fi
    echo
  # else
  #   ns_sub="fark -y"
  #   ns_msg="Archiving $fpath to $apath"
  fi
  # 2024-11
  # mounted=$(mountpoint $HOME/$TARGET);
  # if [ $? -ne 0 ]; then
  #   $(sshfs $TARGET:/ $HOME/$TARGET)
  # fi
  mkdir -p "$apath"
  if ! [ $? -eq 0 ]; then
    p "Could not fark" "Couldnt mkdir -p $apath\ninvoked as fark ${args[@]}"
    exit 1;
  fi
  bn=$(basename "$fpath")
  record_archive_history "${fpath}" "${apath}"
  cp -fr "$fpath" "$apath"
  if [ $? -eq 0 ]; then
    rm -rf "$fpath"
    if $ismusic; then
      p "farked $bn" "Archived $fpath to $apath\nsyncing music."
      out=$(sync_music)
      ret=$?
      if [ $ret -gt 0 ]; then 
        p "post fark error" "Error $ret while syncing music:\n$out"
        exit $ret
      else
        exit 0
      fi
    elif $isimage; then 
      p "farked $bn" "Archived $fpath to $apath\nsyncing images."
      # 2024-11
      # synced="$(rsync -rltuv --delete $HOME/$TARGET/$VIDLIB/$PHOTOLIB $HOME/Pictures/);"
      out="$(rsync -rltuv --delete "$PHOTOLIB/"* $cache/$tempvidlib/$photoname/);"
      ret=$?
      if [ $ret -eq 0 ]; then
        if tru $resume; then 
          if $isimage; then 
            geeqie --remote --slideshow-start
            geeqie --remote --raise
          fi
        fi
        exit 0
      else
        p "post fark error" "Error $ret while syncing music:\n$out"
        exit $ret
      fi
    else
      p "farked $bn" "Archived $fpath to $apath"
      if $resume; then 
        playerctl -p "$player" next
      fi
      exit 0
    fi
  else
    bn=$(basename "$fpath")
    farked="$apath"/"$bn"
    if [ -f "$farked" ]; then
      msg="$bn was previously archived and exists at $apath. exiting.\n"
    
      geeqie --remote --slideshow-start
      geeqie --remote --raise
    fi
    if [ -z "$msg" ]; then
      msg="something went wrong during archive"
    fi
    if untru $fark_noninteractive; then 
      >2  printf "$msg"
    else
      ns_msg+="\n$msg"
      p "$ns_sub" "$ns_msg"
    fi
    exit 1
  fi
}

#  from https://stackoverflow.com/questions/2683279/how-to-detect-if-a-script-is-being-sourced
# As $_ could be used only once, uncomment one of two following lines

# printf '_="%s", 0="%s" and BASH_SOURCE="%s"\n' "$_" "$0" "$BASH_SOURCE" 
[[ "$_" != "$0" ]] && DW_PURPOSE=sourced || DW_PURPOSE=subshell

[ "$0" = "$BASH_SOURCE" ] && BASH_KIND_ENV=own || BASH_KIND_ENV=sourced; 
if tru $DEBUG; then
  se "proc: $$[ppid:$PPID] is $BASH_KIND_ENV (DW purpose: $DW_PURPOSE)"
fi

if [[ $BASH_KIND_ENV == "own" ]]; then 
  main "$@"
fi
