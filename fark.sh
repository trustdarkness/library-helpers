#!/bin/bash
#
# setup environment
source $HOME/.globals
source $D/util.sh
sosutil
source $LH/util.sh
source $D/user_prompts.sh

SHASUM="/opt/bin/shasum"

# temporary 2024-11 during data recovery
container="/run/media/mt/BB"
tempvidlib="mmzz"
cache="/CityInFlames"
photoname="fodder"

export HISTORY="/$container/$tempvidlib/$VIDLIB/.archive_history"

if ! declare -F "tru" > /dev/null 2>&1; then 
  source "$D/existence.sh"
fi

# Keep a record of each archive we make.  This enables multi level
# undo and search across multiple archive locations.
#
# Positional Args:
#   Arg1 - original file path
#   Arg2 - archived file path
#
# Returns 0 on success
# 2 if could not hash the media file
# 3 if paths aren't setup properly
# 100 if archive history file did not exist and, open prompting to 
#     create it the user said no
# 1 otherwise
function record_archive_history() {
  local fpath="${1:-}"
  local apath="${2:-}"
  local ts=$(fsts)
  local hash
  if ! hash=$($SHASUM -a 256 < "${fpath}"); ret=$?; then 
    error "error $ret could not hash archive history item ${fpath}"
    return 2
  fi
  if [ -d dn=$(dirname "$HISTORY") ]; then 
    if ! [ -f "$HISTORY" ]; then 
      echo "no history file present at $HISTORY, start one?"
      if confirm_yes; then 
        touch "$HISTORY"
      else 
        return 100
      fi
    fi
  else
    error "parent dir $dn for HISTORY does not exist, check globals"
    error "before continuing."
    return 3
  fi
  args=( 
    "${ts}"  
    "${fpath}" 
    "->" 
    "${apath}"
    "${hash}"
  )
  printf -v entry "%s\t" "${args[@]}"
  if echo "${entry}" >> "$HISTORY"; then 
    return 0
  fi
  return 1
}

# Returns an archived media back to its original file location
# using the archive history file.  Respects the -y flag, i.e.
# non-interactive or quiet, otherwise prompts the user for confirmation.
# When in non-interactive mode, reports status through notify-send
# if available, otherwise status to console.
# 
# On success, removes the undone archive from the archive history file
# and exits 0, otherwise exists 1
function undo_archive() {
  reverse_fpath_line=$(tail -n 1 "${HISTORY}" |awk -F '>' '{print$1}')
  reverse_fpath="${reverse_fpath_line:16:-2}"
  reverse_apath_line=$(tail -n 1 "${HISTORY}" |awk -F'>' '{print$2}')
  reverse_apath=$(echo "$reverse_apath_line"|awk '{print$1}') # may be brittle if
                                                            # we have spaces in 
                                                            # paths, but i dont 
                                                            # think we do
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
    rm -rf "${fpath}"
    exit 0
  fi
  exit 1
}

# Archives the currently playing or showing media from a number
# of possible players and galleries on localhost or a remote host
# 
# Args:
#  -y: non-interactive or quiet mode, don't prompt the user, assume
#      answers to questions are "yes." don't treat console as interactive
#  -u: undo the last archive
#  -g: special mode for headless geeqie, picks the filename up from 
#      the gallery
#  -r: attempts to resume then the file was taken from a running player
#      or slideshow.  -r takes the app to resume as an arg
#  -d: destination, if other than the default for the media type
#
# Positional Args: the file to be archived
function main() {
  fark_noninteractive=false
  DEBUG=false

  # to report on timing events with returns, we start a second counter
  start=$SECONDS

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
        return 1
        ;;
    esac
  done

  # print wrappers, if we're interactive, we print to the shell
  # otherwise we use notify-send
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

  # if we didn't recieve a filename on the shell, we will try to pick it 
  # up off the clipboard.  this hasn't been used in awhile
  fpath="${@:$OPTIND:1}"
  if [ -z "$fpath" ] && $geeqie; then 
      fpath=$(geeqie --remote --tell)
  elif [ -z "$fpath" ]; then 
    # no filepath supplied, try the clipboard
    fpath="$(xclip -out | xargs)"
    if [ $? -gt 0 ] || [ -z "$dpath" ]; then
      >2 printf "No filename provided and nothing on the clipboard.  Exiting."
      exit 1;
    fi
  fi

  # When running on a remote host, the path needs to be coerced, 
  # this is currently unused and disbled, but left here for possible 
  # future use.
  #
  # echo "is there quotes? $fpath"
  #fpath="$(echo \"$fpath\"|xargs|awk '{"$1"="$1"};1')"
  # prestrip="$(echo $fpath| grep 'file://')";
  # if [ $? -eq 0 ]; then
  #   fpath="$(echo $fpath|cut -d':' -f2|cut -b3-)"
  # fi
  # oldfpath="${dpath}"
  # fpath=$(sanitize_fpath "${dpath}")
  # if "$DEBUG"; then 
  #   se "sanitized fpath: ${fpath}"
  # fi

  # bail if no file
  if ! [ -f "${fpath}" ]; then
      p "could not fark" "no file found at ${fpath}\n invoked as fark ${args[@]}"
      exit 1
  fi
  echo
  
  # 2024-11 - catastrophic data loss during a move meant path changes
  # and some special handling, called out with the date comment.  Maybe
  # someday we'll get to fix.  Special handling for geeqie slideshow.
  echo $fpath|grep $photoname
  if [ $? -eq 0 ]; then
    isimage=true
    geeqie --remote --slideshow-stop
  else
    isimage=false
  fi

  # detect if we're working on a music file and flag
  echo $fpath|grep $MUSICLIB
  if [ $? -eq 0 ]; then
    ismusic=true
  else
    ismusic=false
  fi

  # media types get their own archive locatiouns
  if $isimage; then
    # 2024-11
    # apath="$HOME/$TARGET/$VIDLIB/$PHOTOLIB/archive"
    apath="$PHOTOLIB/archive"

  # for music, the provided argument may have been a song, an
  # album, or an artist.  we try to recursively archive as appropriate
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
      ((ctr++))
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

  # commented lines would have been more path coercion for 
  # running on a remote host that has this host's filesystem
  # mounted.  currently disabled.
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
      # category based archives
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

  # we've done a bunch of string and path manipulation, let's sanity
  # check that we have a source (fpath) and destination (apath) still.
  if [ -z "$fpath" ]; then 
    fready=false
  else
    if [ -f "${fpath}" ]; then 
      fready=true # probably 
    fi
  fi

  if [ -z "$apath" ]; then
    aready=false
  else
    if [ -d "${apath}" ]; then
      aready=true # maybe
    fi
  fi

  # if user supplied a destination with -d, apply it now
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
  donef=$(( SECONDS - start ))
  bn="$(basename "$fpath") in $donef s."
  record_archive_history "${fpath}" "${apath}"

  # all that fuss for this little copy command
  cp -fr "$fpath" "$apath"
  if [ $? -eq 0 ]; then
    rm -rf "$fpath"

    # if this was music we sync changes to our backup archive
    # so it catches the deletes
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

    # again for images, sync deletes to a backup library, and try to resume
    elif $isimage; then 
      donei=$(( SECONDS - start ))
      p "farked $bn" "Archived $fpath to $apath\nsyncing images.\n$donei s."
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

      # otherwise report status and if -r resume
      donee=$(( SECONDS - start ))
      p "farked $bn" "Archived $fpath to $apath. $donee s."
      if $resume; then 
        playerctl -p "$player" next
      fi
      exit 0
    fi
  else

    # if this file was already archived, it should probably be removed
    # TODO: investigate why or why not
    bn=$(basename "$fpath")
    farked="$apath"/"$bn"
    if [ -f "$farked" ]; then
      msg="$bn was previously archived and exists at $apath. exiting.\n"
    fi
    if [ -z "$msg" ]; then
      msg="something went wrong during archive"
    fi
    if untru $fark_noninteractive; then 
      >2 printf "$msg"
    else
      ns_msg+="\n$msg"
      p "$ns_sub" "$ns_msg"
    fi
    exit 1
  fi
}

#  from https://stackoverflow.com/questions/2683279/how-to-detect-if-a-script-is-being-sourced
[ "$0" = "$BASH_SOURCE" ] && BASH_KIND_ENV=own || BASH_KIND_ENV=sourced; 
if tru $DEBUG; then
  se "proc: $$[ppid:$PPID] is $BASH_KIND_ENV (DW purpose: $DW_PURPOSE)"
fi

if [[ $BASH_KIND_ENV == "own" ]]; then 
  main "$@"
fi
