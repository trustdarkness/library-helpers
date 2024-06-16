#!/bin/bash
#
# This is a set of utility functions I regularly use in my bash
# scripting.  It's not specific to the library-helpers general 
# set of functions (which themselves are too specific to probably
# be useful to anyone else outside of my unique environment, but
# I wanted to sync code across devices, and who knows, maybe 
# someone will find something useful to them).
#
# If you intend to use this, you should note that I'm exporting
# all functions for general use and doing so without much 
# concern for name space collision.  If you want to play it more 
# safely, remove all the export lines and source this script in 
# any script that you'd like to utilize some of its functions from.
# Or, of course, you could always just copypasta.
#
# Ive tried to give credit where I used ideas or whole code chunks
# from elsewhere, but have marked the whole repo licensed under 
# GPL v2, because I still think its the best license to protect
# real people from code, but if any of it is yours and you feel 
# the license is inappropriate, please let me know, and I'll take
# it down or come to some other acceptable compromise with you.
# I make no money from any of this, its only for my personal use
# in my home.
#
# May have dependencies on dots/.bashrc and dots/.bash_profile


source $D/user_prompts.sh

# modification of https://stackoverflow.com/questions/229551/how-to-check-if-a-string-contains-a-substring-in-bash
function string_contains() { 
        $(echo "$2"|grep -Eqi $1);
        return $?;
}
export -f string_contains

function sync_music () {
    for pathel in $(echo $MBKS| tr ":" "\n"); do
      synced="$(rsync -rlutv --delete $MUSICLIB $pathel);"
      if [ $? -eq 0 ]; then
        echo "Synced $pathel"
      else
        echo "Something went wrong syncing $pathel"
      fi
    done;
}
export -f sync_music

sanitize_fpath() {
  local fpath="${1:-}"
  if ! [ -n "$fpath" ]; then 
    >2 printf "no path. exiting."
    return 1
  fi
  prestrip="$(echo $fpath| grep 'file://')";
  if [ $? -eq 0 ]; then
    fpath="$(echo $fpath|cut -d':' -f2|cut -b3-)"
  fi
  if string_contains "local" "$fpath"; then
    if string_contains "$VIDLIB" "$fpath"; then
      sedstring="s/\/home\/local/\/$VIDLIB/g"
    else
      sedstring="s/local/$(whoami)\/$TARGET\/$VIDLIB/g"
    fi
    fpath="$(echo $fpath|sed -e $sedstring)";
  fi
  # the path coming from jq over the wire ends up double quoted
  if string_contains '"' $fpath; then 
    sedstring='s/"//g'
    fpath="$(echo $fpath|sed -e $sedstring)"
  fi
  echo "$fpath"
}

# global options to interact with mpv via unix sockets when started with
# --input-ipc-server=/tmp/mpvsocket
# setting up for archiving playing file as wrapper functions around fark
# TODO: allow for more generic player interaction locally and remotely
SOCK="/tmp/mpvsocket"
MPV_SOCK_OPEN="lsof -c mpv|grep $SOCK"
MPV_GET_PROP="get_property"
MPV_PATH_PROP="path"
PLAYING_FILE_IPC_JSON="{ \"command\": [\"$MPV_GET_PROP\", \"$MPV_PATH_PROP\"] }"
NEXT_IPC_JSON="playlist-next"
MPV_SOCK_CMD="echo '%s'|socat - $SOCK|jq .data"
MPV_GET_PLAYING_FILE=$(printf "$MPV_SOCK_CMD" "${PLAYING_FILE_IPC_JSON}")
MPV_NEXT=$(printf "$MPV_SOCK_CMD" "${NEXT_IPC_JSON}")

# rmfark should run properly when run from the player
# host as well as from a remote host.  If this is the player
# host, we simplify.
function rmfark_local() {
  lsof -c mpv|grep /tmp/mpvsocket

  if [[ $? -gt 0 ]]; then
    >2 printf "mpv not listening on $SOCK."
    >2 printf "make sure it was started with"
    >2 printf "--input-ipc-server=/tmp/mpvsocket"
    return 1
  fi
  filepath=$(echo '"{ \"command\": [\"get_property\", \"path\"] }"'|socat - /tmp/mpvsocket|jq .data)
  
  fark "$filepath"
  return $? 
}

# Run fark remotely to archive the currently playing video.
# 
# $TARGET defines the backup host.
# $1 is the player host to get the currently playing video 
#     from.  currently requires player app on player host
#     to be an mpv based player configure to run mpv with
#     --input-ipc-server=/tmp/mpvsocket. Defaults to
#     $DEFAULT_PLAYER. Host access relies on ssh keys. 
function rmfile() {
  remote=false
  if [ -n "$1" ]; then 
    PLAYER=$1
  else
    PLAYER=$DEFAULT_PLAYER
  fi
  if [[ "$PLAYER" == "$(hostname)" ]]; then 
    run="$(rmfark_local)"
    if [ $? -gt 0 ]; then
      >2 printf "rmfark_local failed"
      return 1
    fi
    return 0
  fi
  env_chk="ssh $PLAYER $MPV_SOCK_OPEN"
  se "running $env_chk on $PLAYER"
  env_ok=$($env_chk)
  r=$?
  if [ $r -gt 0 ]; then
    >2 printf "$MPV_SOCK_OPEN failed.\n"
    >2 printf "1. Check that you can ssh to $PLAYER\n"
    >2 printf "   (name exists in ~/.ssh/config, ssh keys are distributed,\n"
    >2 printf "    and ssh-agent is running).\n"
    >2 printf "2. Check that the player app on $PLAYER\n"
    >2 printf "    is running mpv with --input-ipc-server=/tmp/mpvsocket.\n"
    return 1
  fi
  se "Running $MPV_GET_PLAYING_FILE on $PLAYER"
  r_cmd="ssh $PLAYER $MPV_GET_PLAYING_FILE"
  filepath="$($r_cmd)"
  if [ $? -gt 0 ]; then
    >2 printf "Non-zero exit status for:\n"
    >2 printf "$r_cmd"
    return 1
  fi
  echo "${filepath}"
  return 0
}

function rmfark() {
  filepath=$(rmfile)
  if [[ "$1" == "-y" ]]; then 
    /home/mt/bin/fark -y "$filepath"
  else
    /home/mt/bin/fark "$filepath"
  fi
}


function untriage() {
  if [ -n "$2" ]; then
    to="$2"
  else 
    to="$(pwd)"
  fi
  mv "$VIDTRIAGE/$1" "$to"
}
complete -F untriage "$VIDTRIAGE"

#
# tiny helper wrapper around ffmpeg to boost the amplitude of a video file
#
function audio_boost () {
  # handle args ()
  db=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --decibels|-d)
        db=${2:-}
        shift
        ;;
      --file|-f)
        file="${2:-}"
        shift
        ;;
      --help|-h)
        printf "Boosts the audio of a video file by \$DB db (default 20)" # Flag argument
        printf "File supplied by -f, OR only arg on the command line OR clipboad."
        printf "Amplitude boost can be overridden with -d or --decibels."
        exit 0
        ;;
      *)
        echo "no flags supplied, assuming $1 is file..."
        file="$1"
        ;;
    esac
    shift
  done

  if  ! [ -n "$file" ]; then
    # no filepath supplied, try the clipboard
    file="`xclip -out`"
  fi
  # not all of these will be used, but chopping it explicitly for
  # readability, because my brain cannot be trusted.
  if [ $db -eq  0 ]; then
    db=20
  fi
  bn=$(basename "$file");
  path=$(dirname "$file");
  db_string="$db"dB
  mv "$file" /tmp
  bn=$(printf '%q' "$bn")
  ffmpeg_cmd="ffmpeg -i /tmp/$bn -vcodec copy -af \"volume=$db_string\" $bn"
  printf "running  $ffmpeg_cmd"
  boost=$($ffmpeg_cmd)
  if [ $? -eq 0 ]; then
    echo "Boosted $bn by $db db, saved  in $path.  Check the original in /tmp"
    echo "before rebooting if you think there were any re-encoding problems."
  else
    >2 printf "Something went wrong trying to boost with ffmpeg.\n"
    return 1;
  fi
}

function rmaudio_boost() {
  fpath=$(rmfile)
  fpath=$(sanitize_fpath "${fpath}")
  audio_boost -f "${fpath}"
}

function vtrim() {
  ltrim=0
  rtrim=0
  POSITIONAL_ARGS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      -l|--left-trim)
        ltrim=$2
        shift # past argument
        shift # past value
        ;;
      -r|--right-trim)
        rtrim=$2
        shift # past argument
        shift # past value
        ;;
      -h|--help)
        echo "This is a simple wrapper to trim video files of leading"
        echo "or trailing content."
        echo ""
        echo "-l, --left-trim \$secs -- trim the beginning of the video by X secs"
        echo "-r, --right-trim \$secs -- trim the end of the video by X secs."
        echo "-h, --help -- this friendly help text."
        shift # past argument
        shift # past value
        ;;
      -*|--*)
        echo "Unknown option $1"
        return 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        ;;
    esac
  done
  set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

  if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
    filename="`xclip -out`"
  else
    filename="$1"  
  fi
  if [ $ltrim -ne 0 ]; then
    echo "trimming $ltrim seconds from the beginning of $filename."
    echo "(moving original to /tmp)"
    dir="$(pwd)"
    mv "$filename" /tmp/
    attempt=$(ffmpeg -i "/tmp/$filename" -ss $ltrim -acodec copy "$dir/$filename"|pv)
    if ! [ $? -eq 0 ]; then
      >2 printf "Something went wrong trying to left trim $filename. exiting.\n"
      return 1
    fi
  fi
  if [ $rtrim -ne 0 ]; then
    echo "trimming $rtrim seconds from the end of the downloaded video."
    echo "(moving original to /tmp)"
    dir="$(pwd)"
    mv "$filename" /tmp/
    attempt=$(ffmpeg -i "/tmp/$filename" -t $rtrim -vcodec libx264 0 -acodec copy "$dir/$filename"|pv)
    if ! [ $? -eq 0 ]; then
      >2 printf "Something went wrong trying to left trim $filename. exiting.\n"
      return 1
    fi
  fi
}
export -f vtrim

# Some wrappers around the wonderful yt-dlp... an alias just to capture the 
# options I like to use but don't love to type.
function ytd () { 
  /usr/local/bin/yt-dlp \
    --restrict-filenames \
    --windows-filenames \
    --trim-filenames 40 \
    --no-mtime \
    --legacy-server-connect \
    --embed-thumbnail 
  $@
}
export -f ytd

function ytm () {
  /usr/local/bin/yt-dlp \
    -x \
    --audio-format mp3 \
    $@
}
export -f ytm

function ytmp () {
  /usr/local/bin/yt-dlp \
    --yes-playlist \
    -x \
    --audio-format mp3 \
    $@
}
export -f ytmp                                                                      

# And some things to help handle input and optionally boost the 
# audio after pulling the video down. 
function yt () {
  ltrim=0
  rtrim=0
  DB=0
  POSITIONAL_ARGS=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -a|--audio-boost)
        DB=$2
        echo "Capturing output and enabling second stage audio boost by $DB dB"
        shift # past argument
        shift # past value
        ;;
      -l|--left-trim)
        ltrim=$2
        shift # past argument
        shift # past value
        ;;
      -r|--right-trim)
        rtrim=$2
        shift # past argument
        shift # past value
        ;;
      -h|--help)
        echo "This is a simple wrapper around yt-dlp.  At the moment,"
        echo "you can't supply your own arguments to yt-dlp, but have"
        echo "to accept my defaults, which look like:"
        echo ""
        echo "$(alias ytd) \$url"
        echo "(you have to supply the url)"
        echo ""
        echo "but you get extra arguments in return:"
        echo "-a, --audio-boost \$DB -- boost audio in the downloaded video by how many db, default 50"
        echo "-l, --left-trim \$secs -- trim the beginning of the video by X secs"
        echo "-r, --right-trim \$secs -- trim the end of the video by X secs."
        echo "-h, --help -- this friendly help text."
        shift # past argument
        shift # past value
        ;;
      -*|--*)
        echo "Unknown option $1"
        return 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        ;;
    esac
  done

  set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

  if [ $# -eq 0 ]; then
  # no filepath supplied, try the clipboard
    url="`xclip -out`"
  else
    url="$1"  
  fi
  echo "Using yt-dlp to download $url..."

  out=$(ytd "$url"|grep "Adding thumbnail to")
  if ! [ $? -ne 0 ]; then
    >2 printf "Something went wrong calling yt-dlp.\n"
    return 1;
  fi

  filename="$(echo $out|cut -d"\"" -f2)" # |sed 's/.$//');

  if [ $DB -ne 0 ]; then
    echo "trying to boost audio on $out by 50dB,"
    attempt=$(audio_boost "$filename");
    if ! [ $? -eq 0 ]; then
      >2 printf "Something went wrong trying to boost the audio of $filename. Exiting.\n"
      return 1
    fi
  fi
  if [ $ltrim -ne 0 ]; then
    vtrim -l $ltrim $filename
  fi
  if [ $rtrim -ne 0 ]; then
    vtrim -r $rtrim $filename
  fi
  echo "Saved to $filename."
}
export -f yt

