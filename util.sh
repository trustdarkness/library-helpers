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
export -f get_keypress

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
export -f get_yes_keypress

# Prompt to confirm, defaulting to YES on <enter>
function confirm_yes {
  local prompt="${*:-Are you sure} [Y/n]? "
  get_yes_keypress "$prompt" 0
}
export -f confirm_yes

# modification of https://stackoverflow.com/questions/229551/how-to-check-if-a-string-contains-a-substring-in-bash
function stringContains() { 
        $(echo "$2"|grep -Eqi $1);
        return $?;
}
export -f stringContains

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

#
# tiny helper wrapper around ffmpeg to boost the amplitude of a video file
#
function audio_boost () {
  # handle args ()
  db=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --decibels*|-d*)
        if [[ "$1" != *=* ]]; then shift; fi # Value is next arg if no `=`
        db=${1#*=}
        ;;
      --file*|-f*)
        if [[ "$1" != *=* ]]; then shift; fi
        file="${1#*=}"
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
  boost=$(ffmpeg -i "/tmp/$bn" -vcodec copy -af "volume=$db_string" "$file")
  if [ $? -eq 0 ]; then
    echo "Boosted $bn by $db db, saved  in $path.  Check the original in /tmp"
    echo "before rebooting if you think there were any re-encoding problems."
  else
    >&2 printf "Something went wrong trying to boost with ffmpeg.\n"
    return 1;
  fi
}
export -f audio_boost

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
  echo "Using yt-dlp to download $url..."
  if [ $ltrim -ne 0 ]; then
    echo "trimming $ltrim seconds from the beginning of the downloaded video."
    echo "(moving original to /tmp)"
    bn=$(basename $filename)
    mv $filename /tmp/
    attempt=$(ffmpeg -i /tmp/$bn -ss $ltrim -acodec copy $filename|pv)
    if ! [ $? -eq 0 ]; then
      >&2 printf "Something went wrong trying to left trim $filename. exiting.\n"
      return 1
    fi
  fi
  if [ $rtrim -ne 0 ]; then
    echo "trimming $rtrim seconds from the end of the downloaded video."
    echo "(moving original to /tmp)"
    bn=$(basename $filename)
    mv $filename /tmp/
    attempt=$(ffmpeg -i /tmp/$bn -t $rtrim -vcodec libx264 0 -acodec copy $filename|pv)
    if ! [ $? -eq 0 ]; then
      >&2 printf "Something went wrong trying to left trim $filename. exiting.\n"
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
    >&2 printf "Something went wrong calling yt-dlp.\n"
    return 1;
  fi

  filename="$(echo $out|cut -d"\"" -f2)" # |sed 's/.$//');

  if [ $DB -ne 0 ]; then
    echo "trying to boost audio on $out by 50dB,"
    attempt=$(audio_boost "$filename");
    if ! [ $? -eq 0 ]; then
      >&2 printf "Something went wrong trying to boost the audio of $filename. Exiting.\n"
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

