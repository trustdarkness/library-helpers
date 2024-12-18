#!/bin/bash
#
# This is a set of utility functions I regularly use in my bash
# scripting.  It's not specific to the library-helpers general 
# set of functions (which themselves are too specific to probably
# be useful to anyone else outside of my unique environment, but
# I wanted to sync code across devices, and who knows, maybe 
# someone will find something useful to them).
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
# May have dependencies on 
# dots/util.sh  
# dots/filesystemarrayutil.sh
# dots/user_prompts.sh

# if not sourcing .bashrc, you'll want $D to point to a dir containing
# files in my dots repo
# if [ -z $D ]; then 
#   D="$HOME/src/github/dots"
# fi


#####################  internal logging and bookkeeping funcs
#############################################################

# colors for logleveled output to stderr
TS=$(tput setaf 3) # yellow
DBG=$(tput setaf 6) # cyan
INF=$(tput setaf 2) # green
WRN=$(tput setaf 208) # orange 
ERR=$(tput setaf 1) # red
STAT=$(tput setaf 165) # pink
VAR=$(tput setaf 170) # lightpink
CMD=$(tput setaf 36) # aqua
MSG=$(tput setaf 231) # barely yellow
RST=$(tput sgr0) # reset

# load utility libs
if ! declare -F "confirm_yes" > /dev/null 2>&1; then
  source "$D/user_prompts.sh"
fi

if ! declare -F "string_contains" > /dev/null 2>&1; then
  source "$D/util.sh"
fi
 
#      TIMESTAMP [FUNCTION] [LEVEL] PID FILENAME:LINENO
LOGFMT="${TS}%12s [%s] %s %s %s"
if [ -n "$XDG_STATE_HOME" ]; then 
  LH_LOGHOME="$XDG_STATE_HOME/library_helpers"
else
  LH_LOGHOME="$HOME/.local/state/library_helpers"
fi
mkdir -p "$LH_LOGHOME"
LOGFILE="$LH_LOGHOME/util.log"
touch "$LOGFILE"

LOG_LEVELS=( ERROR WARN INFO DEBUG )

# Given a log level name (as above), return
# a numeric value
# 1 - ERROR
# 2 - WARN
# 3 - INFO
# 4 - DEBUG
get_log_level() {
  idx=0
  for level in "${LOG_LEVELS[@]}"; do 
    if [[ "$level" == "${1:-}" ]]; then 
      echo $idx
      return 0
    fi
    ((idx++))
  done 
  return 1
}

# Strip any coloring or brackegs from a log level
striplevel() {
  echo "${1:-}"|sed 's/\x1B\[[0-9;]*[JKmsu]//g'|tr -d '[' |tr -d ']'
}

# based on the numeric log level of this log message
# and the threshold set by the current user, function, script
# do we echo or just log?  If threshold set to WARN, it 
# means we echo WARN and ERROR, log everything
to_echo() {
  this_log=$(get_log_level "${1:-}")
  threshold=$(get_log_level "${2:-}")
  if [ "$this_log" -le "$threshold" ]; then 
    return 0
  fi
  return 1
}

# Log to both stderr and a file (see above).  Should be called using
# wrapper functions below, not directly
_log() {
  local timestamp=$(fsts)

  local pid="$$"
  local src=$(basename "${BASH_SOURCE[0]}")
  local funcname="${FUNCNAME[2]}"
  local level="$1"
  shift
  local message="$@"
  printf -v line_leader "$LOGFMT" "$timestamp" "$funcname" "$level" "${pid}$MSG" \
    "$src" 
  (
    mkdir -p "$LH_LOGHOME"
    this_level=$(stripc "$level")
    if to_echo $this_level $LEVEL; then 
      #exec 3>&1 
      # remove coloring when going to logfile 
      echo "$line_leader $message${RST}" 2>&1 | sed 's/\x1B\[[0-9;]*[JKmsu]//g' | tee "$LOGFILE" 
    else
      echo "$line_leader $message${RST}" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "$LOGFILE"
    fi
  )
}

# Templates for colored stderr messages
printf -v E "%s[%s]" $ERR "ERROR"
printf -v W "%s[%s]" $WRN "WARN"
printf -v I "%s[%s]" $INF "INFO"
printf -v B "%s[%s]" $DBG "DEBUG"

# wrappers for logs at different levels
error() { 
  _log $E "$@"
}

warn() { 
  _log $W "$@"
}

info() { 
  _log "$I" "$@" 
}

debug() { 
  _log "$B" "$(pvars) $@" 
}

################# helper functions for catching and printing
# errors with less boilerplate (though possibly making it 
# slightly more arcane).  an experiment

# print status, takes a return code
prs() {
  s=$1
  printf "${STAT}\$?:$RST %d " "$s"
}

# print variables, takes either a list of variable names
# (the strings, not the vars themselves) or looks in a 
# global array ${logvars[@]} for same
prvars() {
  if [ $# -gt 0 ]; then 
    arr=($@)
  else 
    arr=(${logvars[@]})
    logvars=()
  fi
  for varname in "${arr[@]}"; do 
    n=$varname
    v="${!n}"
    printf "${VAR}%s:${RST} %s " "$n" "$v"
  done     
}

# prints command, arguments, and output
prcao() {
  c="${1:-}"
  a="${2:-}"
  o=$(echo "${3:-}"|xargs)
  e=$(echo "${4:-}"|xargs)
  printf "${CMD}cmd:$RST %s ${CMD}args:$RST %s ${CMD}stdout:$RST %s ${CMD}stderr:$RST %s " "$c" "$a" "$o" "$e"
}

# print a structured error, when the command with arguments, 
# other relevant vars, exit status, and output, says all that needs
# to be said
# Args: return code, command, args, output, stderr
struct_err() {
  ret=$1
  cmd=$2
  args=$3
  out=$4
  err=$5
  retm=$(prs "$ret")
  varsm=$(prvars)
  com=$(prcao "$cmd" "$args" "$out" "$err")
  printf -v error_msg "%s %s %s" "$retm" "$varsm" "$com"
  error "$error_msg"
}

# runs a command, wrapping error handling
# args: command to run, args
lc() {
  cmd="$1"; shift
  #info "lc: $cmd $@"
  {
      IFS=$'\n' read -r -d '' err;
      IFS=$'\n' read -r -d '' out;
      IFS=$'\n' read -r -d '' ret;
  } < <((printf '\0%s\0%d\0' "$($cmd $@)" "${?}" 1>&2) 2>&1)
  if [ $ret -gt 0 ]; then 
    struct_err "$ret" "$cmd" "$@" "$out" "$err"
    return $ret
  else
    echo "$out" && return 0
  fi
}

# simple / generic progress bar 
# Args: finished, total, message
# where total is the number of steps until the task is complete
# finished is how many steps we've finished until now
# message is a message to print to the side of the progress bar while continue
# to use, first run progress_init outside your work loop, then call
# progress from inside the loop, moving finished closer to total with 
# each loop iteration (hopefully)
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
  echo -ne "\\r$INF[${BAR_SIZE:0:percBar}] $RST$perc %  $message $finished / $total $CLEAR_LINE"
}

# prints the first line of the status bar with echo -ne '\\r'
# as long as you don't print anything else, the bar will stay
# put and rewrite itself.
progress_init() {
  echo -ne "\\r[${BAR_SIZE:0:0}] 0 %$CLEAR_LINE"
}

# regex for video files
printf -v VIDEOS_EREGEX "%s" '(.*.mkv$|.*.mp4$|.*.webm$|.*.VOB$|.*.tmp$|.*.part$)'

############################### Library tidying functions
#########################################################


# remove all .DS_Store files from a directory tree, created by
# the overzealous macos, but unused on linux
# to get the mac os to not create these files on network shares, you can run
# defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool TRUE
remove_DS() {
  rejects=(".DS_Store" "._.DS_Store")
  for reject in "${rejects[@]}"; do 
    out=$(find . -name "$reject" -exec rm -f {} \; 2>&1)
    info "${STAT}exit:$RST $? ${CMD}cmd:$RST !! ${MSG}out:$RST $out"
  done
  return 0
}

# convert webp files to png, or if animated, gif.  See usage
# for details.
webp_to_gif_or_png() {
  usage() {
    cat <<EOF
      webp_to_gif_or_png - convert webp files.
     
      Converts webp files in the current dir (recursively) to either gif or png
      as appropriate, optionally deleting the webp files when finished

      Requires libwebp and imagemagick.  Mogrify from graphicsmagick.*compat
      on debian based distros not sufficient.

      Args:
        -q - quiet, no prompts, no informational display.  combined with
            -y, will attempt installs and delete webps of successfully
            converted files.
        -y - yes, answer yes to all prompts
        -p - display a progress bar for conversions
        -v - set loglevel to DEBUG, display all messages, cannot be combined
            with -q or -p

      If requirements not available, we try to install them, prompting
      the user.  If user says no, return 100. If we try to install and fail, 
      return 99.

      Otherwise, return 0 on success, number of failed conversions on fail.
      offer to delete webp files when finished if no failures.
EOF
  }
  quiet=false
  verbose=false
  progress=false
  yes=false
  optspec="qvpy"
  unset OPTIND
  while getopts "${optspec}" optchar; do
    local OPTIND
    local optchar
    case "${optchar}" in
      q)
        quiet=true
        LEVEL=ERROR
        ;;
      y)
        yes=true
        ;;
      v)
        quiet=false
        LEVEL=DEBUG
        progress=false
        ;;
      p)
        progress=true
        LEVEL=ERROR
        ;;
      h | ?) 
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  ms1=ANMF
  ms2=ANIM
  senq() {
    if ! quiet; then 
      se "$@"
    fi
  }
  check_requirements() {
    binary="${1:-}"
    package="${2:-}"
    if ! $(type -p "$binary" > /dev/null 2>&1); then
      senq "Requires $package, attempt to install?"
      if confirm_yes || $yes; then 
        if ! sai $package; then 
          senq "Automated install failed. Please install $package to continue."
          return 99
        fi
      else 
        return 100
      fi
    fi
  }
  check_requirements dwebp libwebp
  check_requirements mogrify imagemagick


  failures=()
  declare -a to_convert_or_delete
  to_convert_or_delete=()
  while IFS= read -r -d $'\0'; do
    to_convert_or_delete+=("$REPLY") # REPLY is the default
  done < <(find "." -regex ".*.webp" -print0 2> /dev/null)
  total=${#to_convert_or_delete[@]}
  if $progress; then 
    progress_init
  fi
  ctr=0
  for i in "${to_convert_or_delete[@]}"; do
    gifret=
    pngret=
    gifout=
    pngout=
    printf -v qfilename "%s" "$i"
    if grepout=$(grep -e $ms1 -e $ms2 "$i" 2>&1); then 
      logvars=("grepout" "ms1" "ms2")

      gifout=$(mogrify -format gif "$qfilename" 2>&1); gifret=$?
      if [ $ret -gt 0 ]; then
        msg="mogrify -format gif \"$qfilename\" failed with ${STAT}code:${RST}"
        msg+=" $gifret ${CMD}output: ${RST}$gifout"
        warn "$msg"
        failures+=( "$qfilename" )
      fi
    else
      pngname="${qfilename/webp/png}"
      if pngout=$(dwebp "$qfilename -o $pngname" 2>&1); pngret=$?; then 
        mv "$qfilename" /tmp/
        if [ $? -gt 0 ]; then 
          msg="mv $qfilename /tmp failed with ${STAT}code: "
          msg+="${RST}$pngret ${CMD}output:$RST $pngout"
          warn "$msg"
        fi
      else
        msg="dwebp $qfilename -o $pngname failed with ${STAT}code:$RST "
        msg+="$pngret ${CMD}output:$RST $pngout"
        warn "$msg"
        failures+=( "$i" )
      fi
    fi
    ctype=
    if [ -n "$gifret" ] && [[ $gifret == 0 ]]; then 
      info "converted $qfilename to ${qfilename/webp/gif}"
      ctype="gif"
    elif [ -n "$pngret" ] && [[ $pngret == 0 ]]; then 
      info "converted $qfilename to $pngname"
      ctype="png"
    else
      info "error converting $qfilename"
      ctype="err"
    fi
    ((ctr++))
    if $progress; then 
      progress "$ctr" "$total" "$ctype"
    fi
  done
  if [ ${#failures[@]} -eq 0 ]; then
    if confirm_yes "Clean out remaining .webp files? " || $yes; then
      out=$(find "." -regex ".*.webp" -exec rm -f {} \; 2>&1); ret=$?
      info "${STAT}exit:$RST $ret ${CMD}cmd:$RST !! ${MSG}out:$RST $out"
    fi
  else
    info "${#failures[@]} out of $total files failed to convert:"
    for file in "${failures[@]}"; do 
      info "  $file"
    done

    senq "See error messages above or logfile at $LOGFILE for more info."
  fi
  return ${#failures[@]}
}



# global options to interact with mpv via unix sockets when started with
# --input-ipc-server=/tmp/mpvsockets/main
# setting up for archiving playing file as wrapper functions around fark
# TODO: allow for more generic player interaction locally and remotely
# SOCK="/tmp/mpvsockets/main"
# MPV_SOCK_OPEN="lsof -c mpv|grep $SOCK"
# MPV_GET_PROP="get_property"
# MPV_PATH_PROP="path"
# PLAYING_FILE_IPC_JSON="{ \"command\": [\"$MPV_GET_PROP\", \"$MPV_PATH_PROP\"] }"
# NEXT_IPC_JSON="playlist-next"
# MPV_SOCK_CMD="echo '%s'|socat - $SOCK|jq .data"
# MPV_GET_PLAYING_FILE=$(printf "$MPV_SOCK_CMD" "${PLAYING_FILE_IPC_JSON}")
# MPV_NEXT=$(printf "$MPV_SOCK_CMD" "${NEXT_IPC_JSON}")
# URLREGEX='https.*' #?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})'

############################### VLC IPC Remote Control
######################################################


# launches vlc with the ipc server at the specified port, default 4445
# and sends it to the background
function vlc_ipc() {
  vlc -I lua:http:rc --rc-host="127.0.0.1:${1:-4445}" --recursive=expand --verbose=1 &
}

# connects to vlcs interactive ipc command line at the given port
# default 4445
function cvlc() {
  nc 127.0.0.1 ${1:-4445}
}

# get full path to currently playing media on vlc
function vlcplaying() {
  url=$(playerctl --player="vlc" metadata |grep ':url' | awk '{$1=$2=""; print $0}' |sed "s@file://@@")
  echo $(urldecode "$url")
}

# sends a raw command over ipc to vlc at the given port
# defaults to 4445
function vlc_send_command() {
  usage() {
    cat<<EOF
    sends a raw command over ipc to vlc at the given port

    Args:
      -p - port of the vlc ipc interface, defaults to 4445
      -h - prints this text

    Positional args:
      Forwarded raw to VLC's command interpreter, its output
      is echoed back to the shell.  
      
    If we detect an error, such as "Unknown command"
    we try to return an error, otherwise return 0.
EOF
  }
  port=4445
  optspec="ph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  command="$@"
  if tru $DEBUG; then 
    debug "command: $command $RST called from ${FUNCNAME[1]}: ${BASH_LINENO[1]}"
  fi
  output=$( (cat <(echo "$command");) |nc -q 0 127.0.0.1 $port 2>&1 | 
  while IFS=$'\n' read -r line; do
    echo "$line" 2>&1
  done ) || return $?
  if string_contains "Unknown" "$output"; then 
    return 1
  fi
  if tru $DEBUG; then 
    debug "$DBG $FUNCNAME output: $output $RST"
  fi
  echo "$output"
  return 0
}

# extracts a filename from vlc's ipc search output
function line_to_name() {
  line="${1:-}"
  stripline=$(echo "$line"|tr -d '|')
  nameandlength=$(echo "${stripline}" | cut -d "-" -f 2-)
  if out=$(string_contains ':' "$nameandlength"); then 
    name="${nameandlength::-11}"
  else 
    name="$nameandlength"
  fi
  echo "$name"
  return 0
}

# extracts an index from vlcs ipc search output
line_to_idx() {
  line="${1:-}"
  stripline=$(echo "$line"|tr -d '|')
  idx=$(echo "$stripline"|awk '{print$1}'|tr -d '*') 
  echo "$idx"
  return 0
}

# searches the vlc playlist for available files
# returning a table with index and filename.
# -q removes the table header, -i returns only 
# indexes
function vlc_playlist_search() {
  usage() {
    cat <<EOF
    vlc_playlist_search - search vlc's current playlist over ipc

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Echos a list of found files and their indexes (internal to the 
    playlist) to the console like:

    idx   name
    2     the_funkstones.mp4
    ...

    Args:
      -i - print indexes only, no names
      -q - quiet: don't print table header
      -p - port number of vlc's ipc interface
      -h - print this text

    Returns 0 on successful search, 255 if no hits
EOF
  }
  indexes_only=false
  quiet=false
  optspec="iq"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      i)
        indexes_only=true
        ;;
      q)
        quiet=true
        ;;
      p) 
        port=4445
        ;;
      h)
        usage
        return 0
        ;;
      *)
        usagge
        return 1
        ;;
    esac
  done
  shift $(($OPTIND - 1))
  searchterm="${1:-}"
  output="$(vlc_send_command -p "$port" search $searchterm)"

  hits=$(grep "^|   [[:space:]]*[0-9]* -" <(echo "$output"))
  debug "$hits"
  if [ -z "$hits" ]; then 
    return 255
  fi

  if ! $quiet; then 
    if $indexes_only; then 
      echo "index"
    else
      echo "index   name"
    fi
  fi
  local IFS=$'\n'
  for hit in $hits; do 
    idx=$(line_to_idx "$hit")
    if $indexes_only; then 
      echo "$idx"
    else
      name=$(line_to_name "$hit")
      echo "$idx    $name"
    fi
  done
  return 0
}

# deletes files (from the playlist, not the disk) based on a vlc
# ipc search.  prompts for confirmation
function vlc_playlist_delete_search() {
  usage() {
    cat <<EOF
    vlc_playlist_delete_search -p <port> <search_term>

    vlc_playlist_delete_search - delete items from the current playlist
    based on an ipc search 

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Prompts the user with results and asks for confirmation before deleting
    and deletes from the playlist, not the disk.
    ...

    Args:
      -p - port number of vlc's ipc interface
      -h - print this text

    Returns 100 if user prompted and answers no
    Returns 101 if malformed data in the search results
    Returns number of failures if deletions failed or 0 on success.
EOF
  }
  port=4445
  optspec="ph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"
  searchterm="${1:-}"
  failures=0
  found=v$(vlc_playlist_search -p "$port" -q "$searchterm")
  echo "These are the files that matched search term $searchterm:"
  echo
  echo "$found"
  if ! confirm_yes "Are you sure you want to remove them?"; then
    return 100
  fi
  local IFS=$'\n'
  for row in $found; do
    idx=$(echo "$row"|awk '{print$2}')
    if ! is_int "$idx"; then 
      error "idx is not an int, malformed data to playlist delete search"
      return 101
    fi
    if ! out="$(vlc_send_command -p "$port" delete $idx)"; then 
      error "$searchterm failed to delete: $out"
      ((failures++))
    fi
  done
  return $failures
}

# deletes a file from the playlist (not the disk) given the file's index
# from vlc_playlist_search
function vlc_playlist_delete_idx() {
  usage() {
    cat <<EOF
    vlc_playlist_delete_idx -p <port> <idx>

    vlc_playlist_delete_idx - delete items from the current playlist
    busing vlc's internal playlist index

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Checks to ensure the index item exists before deletion and is gone
    after attempted deletion.
    ...

    Args:
      -p - port number of vlc's ipc interface
      -h - print this text

    Returns 255 on malformed input
    Returns number of failures if deletions failed or 0 on success.
EOF
  }
  port=4445
  optspec="ph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"
  failures=0
  for idx in "$@"; do
    if ! is_int "${idx}"; then
      idx=$(line_to_idx "$idx")
      if ! is_int "${idx}"; then
        msg="malformed input:$idx called from ${FUNCNAME[1]}: ${BASH_LINENO[1]}"
        error "$msg"
        return 255
      fi
    fi
    if out=$(vlc_send_command -p "$port" item $idx | grep $idx); then 
      vlc_send_command -p "$port" delete $idx
      if out=$(vlc_send_command -p "$port" item $idx | grep $idx); then 
        error "delete command failed."
        ((failures++))
      fi
    else
      warn "idx $idx not found."
      ((failures++))
    fi
  done
  return $failures
}

# get the highest numbered index in the current playlist.
# roughly analagous to playlist length
function vlc_get_max_idx() {
  usage() {
    cat <<EOF
    vlc_get_max_idx -p <port>

    gets the highest number index from the current playlist -- as a proxy 
    to playlist length.

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Args:
      -p - port number of vlc's ipc interface
      -h - print this text

    Echos the largest index to the console and returns 0 on success, 
    1 otherwise.
EOF
  }
  port=4445
  optspec="ph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"
  output=$((cat <(echo "search"); sleep 1) |nc -q 1 127.0.0.1 $port 2>&1 | 
   while IFS=$'\n' read -r line; do
    echo "$line" 
  done ) || return $?
  last=$(echo "$output" |tail -n 4|head -n 1)
  idx=$(echo "${last:4}" |awk '{print$1}')
  if is_int "$idx"; then 
    echo "$idx"
    return 0
  fi
  return 1
}

# adds a file to vlcs queue
function vlc_enqueue_file() {
  usage() {
    cat <<EOF
    vlc_enqueue_file -p <port> -q <path/to/file>

    Adds the provided filepath to the playlist of the vlc instance whose
    IPC is open at the given port.

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Args:
      -p - port number of vlc's ipc interface
      -q - quiet, do not print info about what we're doing
      -h - print this text

    returns 255 if file not found, 1 if error in options, 0 on success
EOF
  }
  port=4445
  quiet=false
  optspec="qph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      q) 
        quiet=true
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"
  filepath="${1:-}"
  if ! [ -f "${filepath}" ]; then 
    se "no file at ${filepath}"
    return 255
  fi
  bn=$(basename "${filepath}")
  if ! $quiet; then 
    se "adding ${filepath} to the vlc instance running on 4445"
  fi
  out=$(vlc_send_command -p "$port" enqueue "file://${filepath}")
  return $?
}

# if vlc has a playlist loaded, this will start playing a random item on it
function vlc_goto_random() {
  usage() {
    cat <<EOF
    vlc_goto_random -p <port>

    VLC seems to sometimes get "stuck" when interacting with it through IPC, 
    shuffle will just stop.  This function picks a random index in the range
    of the current playlist and starts vlc playing at that file.

    Requires that vlc be started with lua or remote-control enabled like:
      vlc -I lua:http:rc --rc-host="127.0.0.1:4445"

    Args:
      -p - port number of vlc's ipc interface
      -h - print this text

    returns 255 if file not found, 1 if error in options, 0 on success
EOF
  }
  port=4445
  optspec="qph"
  unset OPTIND
  unset optchar
  while getopts "${optspec}" optchar; do
    local OPTIND
    case "${optchar}" in
      p)
        port=${OPTARG}
        ;;
      h)
        usage
        return 0
        ;;
      *) 
        usage
        return 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"
  max=$(vlc_get_max_idx)
  rand=$(echo $((1 + $RANDOM % $max)))
  vlc_send_command -p "$port" goto $rand
}

# Uses xdotool to toggle vlc fullscreen
function vlc_full_screen() {
  w_do vlc 41 key 
}

# Queries DBus to discover if vlc is currently fullscreen
# echos true/false as appropriate and returns 0 if fullscreen
# 1 otherwise.
function vlc_is_fullscreen() {
  if qdbus --session \
      org.mpris.MediaPlayer2.vlc \
      /org/mpris/MediaPlayer2 \
      org.freedesktop.DBus.Properties.Get \
      'org.mpris.MediaPlayer2' 'Fullscreen'; then 
    return 0
  fi
  return 1
}

############################################# Smplayer ini mangling
##########################################################################

# setup environment for merging smplayer.ini with
# our or others templates
smplayer_ini_merge_setup() {
  # globals for interacting with smplayer's config files
  lh_source=$(dirname "${BASH_SOURCE[0]}")
  lh=$(basename $lh_source)
  if [ -n "$XDG_CONFIG_HOME" ]; then 
    if [ -d "$XDG_CONFIG_HOME/smplayer" ]; then 
      SMPLAYER_XDG="$XDG_CONFIG_HOME/smplayer"
      LH_XDG="$XDG_CONFIG_HOME/${lh}"
    fi
  fi
  if ! [ -d "$SMPLAYER_XDG" ]; then 
    SMPLAYER_XDG="$HOME/.config/smplayer"
  fi
  if ! [ -d "$LH_XDG" ]; then 
    LH_XDG="$HOME/.config/${lh}"
  fi 
  if [ -n "$XDG_DATA_HOME" ]; then 
    if [ -d "$XDG_DATA_HOME/${lh}" ]; then 
      CACHE="$XDG_DATA_HOME/${lh}/cache"
    fi
  fi
  if ! [ -d "$CACHE" ]; then 
    CACHE="$HOME/.local/share/library-helpers/cache"
  fi

  SMPLAYER_INI="${SMPLAYER_XDG}/smplayer.ini"
  LH_CONFIG_SMPLAYER="$LH_CONFIGS/smplayer"
  mkdir -p "$LH_CONFIG_SMPLAYER"
  git_smplayer_template="$lh_source/smplayer/template_smplayer.ini"
  if [ -s "$git_smplayer_template" ]; then 
    cp "$lh_source/smplayer/template_smplayer.ini" "$LH_CONFIG_SMPLAYER"
  fi
}

# # merges the most recent smplayer.ini with our selective template
# # of config values
# function smplayer_merge_ini() {
#   ts=$(fsts)
#   local sections_base="$LH_CONFIG_SMPLAYER/$ts"
#   local cd="$sections_base/section_configs"
#   mkdir -p "$cd"
#   mkdir -p "$CACHE"
#   swd="$(pwd)"
#   info "our section templates are at $cd"
#   info "derived from our selective combined template at $LH/smplayer/smplayer.ini"
#   info "we're writing intermediary files to the CACHE at $CACHE"
#   info "assembling a new instance config in section files at $sections_base based on the last"
#   info "good config... or something."
#   cd "$CACHE" || return 1
#   info "$(csplit $SMPLAYER_INI '/\[/' '{*}')"  && sleep 2
#   sections=()
#   for name in "$cd"/*; do 
#     sections+=( "$name" )
#   done
#   percent_sections=( "General" )
#   for file in xx*; do 
#     if [ -s "$file" ]; then
#       info "file: $file sed: sed -i \"$file\" 's/^toolbars_state.*//g'"
#       sed -i 's/^toolbars_state.*//g' "$file" 
#       sed -i 's/^recents.*//g' "$file" 
#       if ! section=$(head -n 1 "$file"|tr -d '['|tr -d ']'); then
#         ret=$? 
#         ${error[@]} "code $ret: $section"
#         return $ret
#       fi
#       if string_contains "%" "$section" && [[ "${section:1:}" != "General" ]]; then 
#         warn "$section with % in title"
#         section="${section:1:}"
#         percent_sections+=( "$section" )
#       fi
#       if [ -z "$section" ]; then 
#         continue
#       fi
#       info "in $(pwd) looping on $file"
#       instance_settings=$(while IFS=$'\n' read -r line; do
#         # Skip empty lines
#         if [[ -n "$line" ]] && ! [[ "$line" =~ ^.*|^\[.* ]]; then
#           echo "$line"
#         fi
#       done < "$file")
#       local IFS=$'\n'
#       for line in "${instance_settings[@]}"; do 
#         if string_contains "=" "$line"; then 
#           info "$line"
#           setting_name=$(echo "$line"| cut -d "=" -f 1)
#           if [ -f "$SECTION_CONFIGS/${section}" ] && [ -n "$setting_name" ]; then
#             info "searching for $setting_name in $SECTION_CONFIGS/${section}"
#             template_version=$(grep "$setting_name" "$SECTION_CONFIGS/${section}")
          
#             if [ $? -eq 0 ] && [ -n "$template_version" ]; then # redundant
#               echo "$template_version" >> "$cd/${section}"
#             else
#               echo "$line" >> "$cd/${section}"
#             fi
#           fi
#         fi
#       done
#     fi
#   done

#   # Now lets pick up any config settings that only existed in the templates
#   for sectionfile in "$cd"/*; do 
#     info "file: $sectionfile from $cd"
#     if [ -s "$sectionfile" ] && [[ "${sections[*]}" == *"$sectionfile"* ]]; then
#       template_settings=()
#       while IFS=$'\n' read -r line; do 
#         template_settings+=("$line")
#       done < "$sectionfile" 
#       # now we asseemble
#       for line in "${template_settings[@]}"; do 
#         setting_name=$(echo "$line"| cut -d "=" -f 1)
#         to_add=$(grep -v "$setting_name" "$cd/$section" > /dev/null 2>&1)
#         if [ $? -eq 0 ] && [ -n "$to_add" ]; then 
#           echo "$line" >> "$sections_base/$sectionfile"
#         fi
#       done
#       cat "$sections_base/$sectionfile" >> "$sections_base/smplayer.ini"
#     fi
#   done
#   if [ -s "$sections_base/smplayer.ini" ]; then
#     mv "$SMPLAYER_INI" "$SMPLAYER_XDG/smplayer.ini.$ts"
#     mv "$sections_base/smplayer.ini" "$SMPLAYER_XDG"
#     echo "$cd"
#     cd "$swd" || cd - || return 99
#     return 0
#   fi
#   return 1
# }

# merges a template of ini settings (where someone has selcted some subset
# of sections and settings they care about, populated only those into
# ini template file) and wants to merge them into the programs normal ini
# file, keeping any other values as is.
# 
# Positional args:
#   sourcefile - the program's normal ini file
#   overwrites - the selective template
#   dest - the merged destination file to create
# 
# Note: this has not been thoroughly tested and may still have issues.
# Use at your own risk
function ini_merge() {
  sourcefile="${1:-}"
  overwrites="${2:-}"
  dest="${3:-}"
  if [ -f "$dest" ]; then 
    if confirm_yes "dest file exists, overwrite?"; then 
      rm -f "$dest"
    else
      return 100
    fi
  fi
  # settings_to_ignore="${4:-}"
  icache="$CACHE/ini_merge"
  mkdir -p "$icache"
  rm -rf "${icache:?}/*"
  ini_split "$sourcefile" "$icache"
  ini_split "$overwrites" "$icache"
  source=$(basename "$sourcefile")
  sourcestem=$(basename "$source" ".ini")
  if ! [ -d "${icache}/${sourcestem}" ]; then 
    error "expected ini_split data in ${icache}/${sourcestem}"
    return 5;
  fi
  over=$(basename "$overwrites")
  overstem=$(basename "$over" ".ini")
  if ! [ -d "${icache}/${overstem}" ]; then 
    error "expected ini_split data in ${icache}/${overstem}"
    return 5;
  fi

  # Now lets pick up any config settings that only existed in the templates
  sections=()
  while IFS=$'\n' read -r line; do 
    sections+=("$line")
  done < "${icache}/${overstem}/section_order"
  for section in "${sections[@]}"; do 

    sectionfile_basename="${overstem}_${section}.ini.part"
    sectionfile="${icache}/${overstem}/$sectionfile_basename"
    if [ -s "$sectionfile" ]; then
      lines_to_add=()

      source_part="${icache}/${sourcestem}/${sourcestem}_${section}.ini.part"
      debug "sourcefile: $source_part overwritefile: $sectionfile"
      if ! [ -s "$source_part" ]; then
        error "$source_part expected but not found."
        return 4
      fi
      overwrite_settings=()
      while IFS=$'\n' read -r line; do 
        overwrite_settings+=("$line")
      done < "$sectionfile" 
      # now we asseemble
      ctr=0
      echo -ne "$ctr matches replaced"
      for line in "${overwrite_settings[@]}"; do 

        setting_name=$(echo "$line"| cut -d "=" -f 1)
        printf -v escaped_setting "%q" "$setting_name"

        found_line=$(grep -n "^${escaped_setting}=.*" "$source_part") 
        if [ $? -eq 0 ]; then 
          # debug "grep -n $escaped_setting found $found_line"
          # info nothin
          line_no=$(echo "$found_line"| awk -F':' '{print$1}')

          if is_int "$line_no"; then 
            if sed -i "${line_no}d" "$source_part"; then 
              lines_to_add+=( "$line" )
              echo -ne "\\r$ctr matches deleted from source"
              ((ctr++))
            else
              error "sed -e ${line_no}d $source_part"
              return 3
            fi
          else
            error "not parsing line number from grep: $found_line $line_no $setting_name $source_part"
            return 4
          fi
        else
          # doublecheck
          if [ -z "$found_line" ]; then 
             # add settings that don't exist in the source
             echo "$line" >> "$source_part"
          fi
        fi

      done
      for line in "${lines_to_add[@]}"; do 
        echo "$line" >> "$source_part"
      done
      echo "[$section_name]" >> "$dest"
      cat "$source_part" >> "$dest" 
    fi
  done
  return 0
}

# splits an .ini file into separate files, one per section
# with the config section name moved to the filename
#
# Positional Args:
#   filename of the ini file to split
#   location for the splits (creates a folder using the filename)
#     defaults to cwd
function ini_split() {
  filepath="${1:-}"
  filename=$(basename "$filepath")
  stem=$(basename "$filename" ".ini")
  target_parent_dir="${2:-$(pwd)}"
  target="${target_parent_dir}/$stem"
  if [ -d "$target" ]; then 
    if confirm_yes "$target exists, overwrite?"; then 
      rm -rf "${target:?}"
    else
      return 100
    fi
  fi
  mkdir -p "$target"

  mkdir -p "$CACHE"
  swd="$(pwd)"
  cd "$CACHE" || return 1
  rm -f xx*
  trap ctrl_c INT
  ctrl_c () {
    cd "$swd" || return 101
    return 100
  }
  # info "$(csplit $filename '/\[/' '{*}')"
  csplit "$filepath" '/^\[/' '{*}' > /dev/null 2>&1
  if ! ls xx* > /dev/null 2>&1; then 
    error "csplit failed"
    return 2
  fi
  sleep 2 # give csplit a second or two

  for file in xx*; do 
    if [ -s "$file" ]; then
      if ! section=$(head -n 1 "$file"|grep '^\['|tr -d '['|tr -d ']'); then
        ret=$? 
        error "code $ret: $section"
        return $ret
      fi
      if [ -z "$section" ]; then 
        continue
      fi
      section_dest="${target}/${stem}_${section}.ini.part"
      touch "$section_dest"
      echo "$section" >> "${target}/section_order"
      out=$(while IFS=$'\n' read -r line; do
        # Skip empty lines
        if [[ -n "$line" ]]; then
          echo "$line" 
        fi
      done < "$file")
      local IFS=$'\n'
      for line in $out; do 
        if ! [[ "$line" =~ ^\[.* ]]; then
          setting=$(echo "$line"|cut -d "=" -f 1)
          printf -v escaped_setting "%q" "$setting"
          # if [[ "$escaped_setting" == "driver"* ]];  then 
          #   debug "$escaped_setting"
          # fi
          out=$(grep "$escaped_setting" "$section_dest")
          if [ -z "$out" ]; then  
            echo "$line" >> "$section_dest"
          else
            flag=0
            for fline in $out; do 
              if [[ "$line" == "$fline" ]]; then
                ((flag++))
              fi
            done
            if [ $flag -eq 0 ]; then  
              echo "$line" >> "$section_dest"
            fi
          
          fi
        fi
      done
    fi
  done
  cd "$swd"|| return 101
  return 0
}

# reassembles an ini file split by ini_split such that it should
# be identical to the original
function ini_reassemble() {
  split_files=${1:-}
  dest=${2:-} 
  if [ -f $dest ]; then 
    if confirm_yes "destination exists, overwrite?"; then 
      rm $dest
    else
      return 100
    fi
  fi
  sections=()
  while IFS=$'\n' read -r line; do 
    sections+=("$line")
  done < "$split_files/section_order"
  for section in "${sections[@]}"; do 
    sourcename="$split_files.ini"
    stem=$(basename $sourcename .ini)
    section_filename="${stem}_${section}.ini.part"
    #section_len=$((${#section_basename}-${#stem}-9))
    # debug "$sourcename $stem $split_files ${#split_files} ${section_basename:${#stem}+1:$section_len-1}"
    sectionheader=$(printf "[%s]\n" $section)
    echo "$sectionheader" >> "$dest"
    cat "$split_files/$section_filename" >> "$dest"
    echo >> "$dest"
  done
}

###################################### Smplayer control via playerctl & xdotool
###############################################################################

# get full path to currently playing media on smplayer
function smplayerplaying() {
  url=$(playerctl --player="smplayer" metadata |grep ':url' | awk '{$1=$2=""; print $0}' |sed "s@file://@@")
  echo $(urldecode "$url")
}

# Uses xdotool to add a file to smplayers queue
function smplayer_enqueue_file() {
  filepath="${1:-}"
  if ! [ -f "$filepath" ]; then 
    se "no file at $filepath"
    return 2
  fi
  echo "$filepath"|xclip -i -se p
  smplayer_add_file_from_clipboard
  return $?
}

# deletes the currently playing media from the playilst
# (not the disk)
# 37 Control_L
# 64 Alt_L
# 58 M
# Note: for playlist operations to succeed, the playlist
#       must be visible and in the foreground
#       call smplayer_playlist_ready
function smplayer_delete_playing() {
  smplayer_do_keys "37+64+58" 
}

# adds a single folder location to the playlist using xdotool
# from the system clipboard
# 64 Alt_L
# 21 equals (=)
# 36 return
# Note: for playlist operations to succeed, the playlist
#       must be visible and in the foreground
#       call smplayer_playlist_ready
function smplayer_add_folder_from_clipboard() {
  smplayer_do_keys "64+21" "false"
  smplayer_do_type "$(xclip -o -se p)"
  smplayer_do_keys "36"
}

# adds a single file from the clipboard to smplayer
# using xdotool
# 64 Alt_L
# 33 p
# 36 return 
# Note: for playlist operations to succeed, the playlist
#       must be visible and in the foreground
#       call smplayer_playlist_ready
function smplayer_add_file_from_clipboard() {
  smplayer_do_keys "64+33" "false"
  smplayer_do_type "$(xclip -o -se p)"
  smplayer_do_keys "36"
}

# uses xdotool to clear the smplayer playlist
# 37 Control_L
# 64 Alt_L
# 46 L
# Note: for playlist operations to succeed, the playlist
#       must be visible and in the foreground
#       call smplayer_playlist_ready
function smplayer_playlist_clear() {
  smplayer_do_keys "37+64+46"
}

# toggles smplayer's shuffle option using xdotool
# 37 Control_L
# 64 Alt_L
# 45 k
# Note: for playlist operations to succeed, the playlist
#       must be visible and in the foreground
#       call smplayer_playlist_ready
function smplayer_toggle_shuffle() {
  smplayer_do_keys "37+64+45"
}

# gets current video geography from mpv, only works
# if smplayer playing, using mpv as the backend, and
# ipc socket at /tmp/mpvsockets/main
function smplayer_get_geometry() {
  json=$(echo '{ "command": ["get_property", "osd-dimensions"] }'| socat - /tmp/mpvsockets/main)
  w=$(echo "$json"|jq .data.w)
  h=$(echo "$json"|jq .data.h)
  printf "%dx%d" "$w" "$h"
}

# toggles the visibility of smplayer's playlist, and
# if the playlist is docked, will use the video geometry
# to determine the state of visibility, writing such state
# to global variable MPLAYER_PLAYLIST_SHOWN
# 37 Ctrl
# 46 L
function smplayer_playlist_toggle() {
  # if ! mpv-active-sockets; then 
  #   smplayer_playlist_ready
  #   sleep 3
  #   if ! mpv_active_sockets; then
  #     se "without SMPlayer actively playing something, an ipc socket"
  #     se "open, and the playlist docked, there's no easy way to tell"
  #     se "whether the playlist is open, programmatically, these are"
  #     se "signals we currently use.  If the playlist gets undocked,"
  #     se "everything goes screwy.  Exercise caution."
  #     se " "
  #     se "Can't find an active socket. Still toggling. YMMV."
  #     smplayer_do_keys "37+46"
  #     return 255
  #   fi
  # fi
  # oldgeo=$(smplayer_get_geometry)
  # oldw=$(echo "$oldgeo" |cut -d x -f 1)
  # oldh=$(echo "$oldgeo" |cut -d x -f 2)
  # smplayer_do_keys "37+46"
  # newgeo=$(smplayer_get_geometry)
  # w=$(echo "$newgeo" |cut -d x -f 1)
  # h=$(echo "$newgeo" |cut -d x -f 2)
  # if gt $w $oldw && gt $h $oldh; then 
  #   SMPLAYER_PLAYLIST_SHOWN=false
  # elif gt $oldw $w && gt $oldh $h; then 
  #   SMPLAYER_PLAYLIST_SHOWN=true
  # else 
  #   se "problem detecting smplayer geometry"
  # fi
  smplayer_do_keys "37+46"
}

# If playlist is docked and mpv playing, this function
# will show the playlist
function smplayer_playlist_show() {
  state=$(grep "playlist visible" "$HOME/.config/smplayer/smplayer_log.txt"|tail -n 1|awk '{print$NF}'|xargs)
  state=${state:0:1}
  if [[ "$state" == "0" ]]; then 
    debug toggle
      smplayer_playlist_toggle
      return 0
  fi
  return 1
}

# If playlist is docked and mpv playing, this function
# will hide the playlist
function smplayer_playlist_hide() {
  state=$(grep "playlist visible" "$HOME/.config/smplayer/smplayer_log.txt"|tail -n 1|awk '{print$NF}'|xargs)
  state=${state:0:1}
  if [[ "$state" == "1" ]]; then 
    debug toggle
      smplayer_playlist_toggle
      return 0
  fi
  return 1
}

# If playlist is docked and mpv playing, this function
# will raise smplayer with the playlist shown so that it 
# is ready for keystroke command input
function smplayer_playlist_ready() {
  # the hacks we use to get the window id and to reproducably make the 
  # playlist viewable require that SMPlayer/mpv be actively playing 
  # something, so we try to play an unrelated file that we'll remove
  # later, based on our expectation we can be sure its there and won't 
  # be too off-putting to the mood.
  if ! pgrep -il smplayer; then 
    smtplayer
    sleep 0.5
  fi
  if ! mpv-active-sockets; then 
    if px smplayer|grep defunct; then 
      pkill -9 smplayer
      smtplayer
      sleep 0.5
    fi
    playerctl -p smplayer next
    sleep 0.5
  fi
  w_do smplayer # raise the window regardless
  sleep 0.5
  smplayer_playlist_show
}

# uses a kde global shortcut to tile smplayer on the 
# left half of the main screen
function smplayer_tile_left() {
  smplayer_do_keys "133+113"
}

# enters keyboard shortcuts to smplayer using xdotool
smplayer_do_keys() {
  keys="${1:-}"
  ret="${2:-true}"
  w_do "smplayer" "$keys" "key" "$ret"
}

# enters text into smplayer using xdotool
smplayer_do_type() {
  in="${1:-}"
  ret="${2:-true}"
  w_do "smplayer" "$in" "type" "$ret"
}

# gets window id for smplayer to be used by xdotool
smplayer_WID() {
  WID=""
  if ! out=$(pgrep -il smplayer 2>&1); then 
    smtplayer &
    sleep 0.5
  fi
  status=$(playerctl -p smplayer status)
  if [[ "$status" == "Playing" ]]; then 
    printf -v wid_search_string '[-][ ]%s' 'SMPlayer'
  else
    wid_search_string='SMPlayer'
  fi
  until [ -n "$WID" ]; do
      WID="$(xdotool search --name "$wid_search_string" 2>/dev/null)"
      info "WID: $WID from xdotool search --name $wid_search_string"
  done
  echo "$WID"
}

############################################ agnostic xdotool helper functions
##############################################################################

# send xdotool commands (type,key and either string or keycodes)
# to the foreground window of the provided command.  If no command
# is given, raises the program
function w_do() {
  local player="${1:-}"
  in="${2:-}"
  type="${3:-}"
  ret="${4:-true}"

  WID=$(lc get_WID "$player")||return $?

  try=''
  for wid in $WID; do
    try="${wid}"
  done
  if [ -n "$try" ]; then 
    WID="$try"
  fi
  logvars=(player WID)
  lc "xdotool" "windowactivate $WID"||return $?

  if [ -n "$in" ]; then # if no args, still raise the window
    info "xdotool $type --window $WID $in"
    sleep 0.1  # http://serverfault.com/a/469249
    lc xdotool "$type --window $WID $in" || return $?; 
    # if tru "$ret"; then 
    #   xdotool windowactivate "$OLD_WID"          # 'remove selected'
    # fi
  fi
  return 0
}
export -f w_do

# gets window id for the given app suitable for xdotool
function get_WID() {
  app="${1:-}"
  if [[ "$app" == "smplayer" ]]; then 
    WID="$(smplayer_WID)"
  else
    WID=$(wmctrl -l|grep -i "$app"|awk '{print$1}')
  fi
  echo "$WID"
}

################################################# media archive (fark) helper
#############################################################################

# run fark (media archive) interactively, giving a choice if multiple 
# players are running
function ifark() {
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

####################################################### media file fixer uppers
######################################## (Audio Boost/Normalize and Video Trim)
###############################################################################

# tiny helper wrapper around ffmpeg to adjust the audio levels of a video file
#
# Args: 
#  -d <int> - raise by so many decibles
#  -n - normalize the audio, disables -d
#  -l <int> - specify a loudness range target for normalization
#  -f <filename> - filename to normalize, or will use first positional arg
#
# the original file is moved to temp and replaced.
function audio_boost () {
  # handle args ()
  db=10
  lrt=20
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
      --loudness-range-target|-l)
        lrt=${2:-}
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
    ffmpeg_args=("/tmp/$bn" "--progress" --loudness-range-target $lrt --keep-lra-above-loudness-range-target "-c:a" "mp3" -o "$path/$bn")
    ffmpeg="ffmpeg-normalize"
    success_string="Normalized $bn, saved in $path."
  else
    ffmpeg_args=("-i" "/tmp/$bn" "-filter:a" "volume=${db}dB" "$path/$bn") 
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

# trim the first and/or last n seconds from a video clip 
# 
# Args:
#   -l <int>: trim <int> seconds from the left or beginning
#   -r <int>: trim <int> seconds from the right or end
# 
# the original file is moved to temp and replaced.
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
      --file|-f)
        filepath="${2:-}"
        shift
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
  if ! [ -f "$filepath" ]; then 
    se "no file at $filepath"
    exit 1 
  fi
  bn=$(basename "$filepath")
  dn=$(dirname "$filepath")
  if [ $ltrim -ne 0 ]; then
    echo "trimming $ltrim seconds from the beginning of $bn."
    echo "(moving original to /tmp)"

    mv "$filepath" /tmp/
    attempt=$(nice -n 2 ffmpeg -i "/tmp/$bn" -ss $ltrim -acodec copy "$dn/$bn")
    if ! [ $? -eq 0 ]; then
      >2 printf "Something went wrong trying to left trim $bn. exiting.\n"
      return 1
    fi
  fi
  if [ $rtrim -ne 0 ]; then
    echo "trimming $rtrim seconds from the end of the downloaded video."
    echo "(moving original to /tmp)"

    mv "$filepath" /tmp/
    attempt=$(nice -n 2 ffmpeg -i "/tmp/$bn" -t $rtrim -vcodec libx264 0 -acodec copy "$dn/$bn")
    if ! [ $? -eq 0 ]; then
      >2 printf "Something went wrong trying to left trim $bn. exiting.\n"
      return 1
    fi
  fi
}
