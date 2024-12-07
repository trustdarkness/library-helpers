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

if [ -z $D ]; then 
  D="$HOME/src/github/dots"
fi

if ! declare -F "confirm_yes" > /dev/null 2>&1; then
  source "$D/user_prompts.sh"
fi

if ! declare -F "string_contains" > /dev/null 2>&1; then
  source "$D/util.sh"
fi

function sync_music () {
  failures=0
  for pathel in $(echo $MBKS| tr ":" "\n"); do
    synced="$(rsync -rlutv --delete $MUSICLIB $pathel);"
    if [ $? -eq 0 ]; then
      echo "Synced $pathel"
    else
      echo "Something went wrong syncing $pathel"
      ((failures++))
    fi
  done;
  return $failures
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
URLREGEX='https.*' #?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})'

ytopts=("-q" "--progress" "--newline" "--progress-delta" "2")

# silly little progress bar example
declare -x BAR_SIZE="##################"
declare -x CLEAR_LINE="\\033[K"
progress() {
  # heavily cribbed from 
  # https://github.com/lnfnunes/bash-progress-indicator/blob/master/progress.sh
  finished="${1:-}"
  total="${2:-}"
  message="${3:-}"
  local MAX_STEPS=$total
  local MAX_BAR_SIZE="${#BAR_SIZE}"
  perc=$(($finished * 100 / MAX_STEPS))
  percBar=$((perc * MAX_BAR_SIZE / 100))
  echo -ne "\\r[${BAR_SIZE:0:percBar}] $perc %  $message - Plugin $finished / $total $CLEAR_LINE"
}

# wrapper for yt-dlp for my Silly little progress bar example
ytprog() {
  echo -ne "\\r[${BAR_SIZE:0:0}] 0 %$CLEAR_LINE"
  url="${@: -1}"
  name=$(echo "$url" | awk -F'/' '{print$NF}')
  pref="${name:0:5}..."
  yt-dlp $@ 2>&1 | 
    while IFS=$'\n' read -r line; do
      finishedp=$(echo "$line"|awk '{print$2}')
      if is_int "${finishedp::-3}"; then 
        finished="${finishedp::-3}"

        progress "$finished" "100" "dling $pref"
      else
        echo "$finishedp"
      fi
    done
}

# for the truly lazy among us who'd like to type as few chars as possible
alias y="yt-dlp -j -q --progress "
function yc() {
  log="/tmp/yc.log"
  a=()
  c=
  p=
  c="$(xclip -o -se c)"
  p="$(xclip -o -se p)"
  a=( "$c" "$p" )
  if [[ "$c" == "$p" ]]; then 
    echo "c: $c"
    ytprog ${ytopts[@]} "$c"
    if [ $? -eq 0 ]; then 
      echo "$c" >> "$log"
      return 0
    fi
  else
    for i in "${a[@]}"; do 
      echo "$i"
      echo "$i" | grep "$URLREGEX" > /dev/null 2>&1
      if [ $? -eq 0 ]; then 
        grep "$i" "$log"
        if [ $? -gt 0 ]; then 
          ytprog ${ytopts[@]} "$i"
          if [ $? -eq 0 ]; then 
            echo "$i" >> "$log"
            return 0
          fi   
        else
          "$i in yc.log"
        fi
      fi
    done
  fi    
  return 1
}

# rmfark should run properly when run from the player
# host as well as from a remote host.  If this is the player
# host, we simplify.
# this function may not be needed any longer
function rmfark_local() {
  filepath=$(smurl)
  
  fark "$filepath"
  return $? 
}

# temporary 20241109 delete or formalize when finished
source ~/.local_lhrc
sp="vlc"

function siurl() {
  url=$(playerctl --player="$sp" metadata |grep ':url' | awk '{$1=$2=""; print $0}' |sed "s@file://@@")
  echo $(urldecode "$url")
}

function smurl() {
  url=$(playerctl --player="smplayer" metadata |grep ':url' | awk '{$1=$2=""; print $0}' |sed "s@file://@@")
  echo $(urldecode "$url")
}

# actually do what rmfark_local was intended to do, but 
# supporting multiple players and prompting if needed
function lfark() {
  declare -a players
  declare -ga titles
  declare -a urls
  players=()
  titles=()
  urls=()
  echo "If there is playing media, you'll see it below..."
  echo
  indexplus1=0
  for player in $(playerctl --list-all); do 
    ((indexplus1++))
    status=$(playerctl --player="$player" status)
    if [[ "$status" == "Playing" ]]; then 
      players+=( "$player" )
      url=$(playerctl --player="$player" metadata |grep url | awk '{$1=$2=""; print $0}' | xargs |sed "s@file://@@")
      urls+=( "$url" )
      # most videos will have a title
      titleline=$(playerctl --player="$player" metadata |grep title)
      if [ $? -gt 0 ]; then 
        # when there's no title, we'll grab the filename from the url
        title=$(basename "$url")
      else 
        title=$(echo "$titleline" |awk '{$1=$2=""; print $0}' | xargs)
      fi
      titles+=( "$title" )
    fi
    echo " $indexplus1. [$player] $title"
  done
  echo
  choice=$(get_keypress "Enter the number of the media file you'd like to archive: ")
  idx_to_del=$(($choice-1))
  fark "${urls[$idx_to_del]}"
  if [ $? -eq 0 ]; then 
    playerctl --player="${players[$idx_to_del]}" next
  fi
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
  SSH=$(type -p ssh)
  remote=false
  if [ -n "$1" ]; then 
    PLAYER=$1
  else
    PLAYER=$DEFAULT_PLAYER
  fi
  # if [[ "$PLAYER" == "$(hostname)" ]]; then 
  #   rmfark_local
  #   if [ $? -gt 0 ]; then
  #     se "rmfark_local failed"
  #     return 1
  #   fi
  #   return 0
  # fi
  env_chk_ssh_args=( "$PLAYER" "$MPV_SOCK_OPEN" )
  se "sshing using ${env_chk_ssh_args[@]} on $PLAYER"
  "$SSH" "${env_chk_ssh_args[@]}"
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
  r_cmd="$SSH $PLAYER $MPV_GET_PLAYING_FILE"
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
  local farkargs=()
  optspec="yud:"
  while getopts "${optspec}" optchar; do
    case "${optchar}" in
      y)
        farkargs+=( "-y" )
        ;;
      u)
        farkargs+=( "-u" )
        ;;
      d)
        path="${OPTARG}"
        if [ -n "$path" ]; then 
          farkargs+=( "-d" )
          farkargs+=( "$path" )
        fi
        ;;
      *)
        help
        ;;
    esac
  done
  # this dpath shouldn't really exist
  host="${@:$OPTIND:1}"
  if [ -n "$dpath" ]; then
    echo "pathtosource normally not applied to rmfark"
    echo "instead its purpose is to pull the filname"
    echo "from the player host"
  fi
  filepath=$(rmfile "$host")
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
  db=10
  normalize=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --decibels|-d)
        db=${2:-}
        shift
        ;;
      --normalize|-n)
        normalize=true
        shift
        ;;
      --file|-f)
        file="${2:-}"
        shift
        ;;
      --help|-h)
        printf "Boosts the audio of a video file by \$db db (default 10)" # Flag argument
        printf "File supplied by -f, OR only arg on the command line OR clipboad."
        printf "Amplitude boost can be overridden with -d or --decibels."
        printf "Or use -n to normalize, if -n supplied, -d is ignored."
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
    file="$(xclip -out)"
  fi
  # not all of these will be used, but chopping it explicitly for
  # readability, because my brain cannot be trusted.
  bn=$(basename "$file");
  path=$(dirname "$file");
  mv "$file" /tmp
  #bn=$(printf '%q' "$bn")
  if $normalize; then 
    if ! type -p pipx > /dev/null 2>&1; then 
      echo "to normalize, ffmpeg-normalize should be installed from pipx"
      echo "but pipx doesn't seem to be installed... attempt to install?"
      if confirm_yes; then 
        install_util_load
        if ! sai pipx; then 
          echo "install failed, install pipx to continue, or use -d to change"
          echo "volume level by db"
          return 2
        fi
      else
        echo "install pipx to normalize, or use -d to change by db"
        return 1
      fi
    fi
    pipx list|grep ffmpeg-normalize > /dev/null 2>&1 
    if [ $? -gt 0 ]; then 
      if ! pipx install ffpeg-normalize; then 
        echo "pipx install ffmpeg-normalize failed.  Install ffmpeg-normalize"
        echo "to continue with -n or use -d to adjust by db."
        return 3
      fi
    fi
    ffmpeg_args=("/tmp/$bn" "--progress" "-c:a" "mp3" -o "$path/$bn")
    ffmpeg="ffmpeg-normalize"
    success_string="Normalized $bn, saved in $path."
  else
    ffmpeg_args=("-i" "/tmp/$bn" "-filter:a" "volume=10dB" "$path/$bn") 
    ffmpeg="ffmpeg"
    success_string="Boosted $bn by $db db, saved  in $path."
  fi
  echo "running $ffmpeg ${ffmpeg_args[@]}"
  nice -n 2 $ffmpeg ${ffmpeg_args[@]}
  if [ $? -eq 0 ]; then
    echo "$success_string Check the original in /tmp"
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
  echo "running with $@"
  /usr/local/bin/yt-dlp \
    --restrict-filenames \
    --windows-filenames \
    --trim-filenames 40 \
    --no-mtime \
    --legacy-server-connect \
    --embed-thumbnail $@
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
        echo "-a, --audio-boost \$DB -- bo
m the beginning of the video by X secs"
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
  echo "num $# arr $@ pa ${POSITIONAL_ARGS[@]}"
  if [ -z "${POSITIONAL_ARGS[*]}" ]; then
  # no filepath supplied, try the clipboard
    url="$(xclip -o)"
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

