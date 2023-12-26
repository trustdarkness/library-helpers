#!/bin/bash
# handle args ()
while [ $# -gt 0 ]; do
  case "$1" in
    --decibels*|-d*)
      if [[ "$1" != *=* ]]; then shift; fi # Value is next arg if no `=`
      DB="${1#*=}"
      ;;
    --file*|-f*)
      if [[ "$1" != *=* ]]; then shift; fi
      FILE="${1#*=}"
      ;;
    --help|-h)
      printf "Boosts the audio of a video file by 50 db" # Flag argument
      printf "File supplied by -f, OR only arg on the command line OR clipboad."
      printf "Amplitude boost can be overridden with -d or --decibels."
      exit 0
      ;;
    *)
      echo "no flags supplied, assuming $1 is file..."
      FILE="$1"
      ;;
  esac
  shift
done

if  ! [ -n "$FILE" ]; then
  # no filepath supplied, try the clipboard
  FILE="`xclip -out`"
fi
# not all of these will be used, but chopping it explicitly for
# readability, because my brain cannot be trusted.
if [ -z "$DB" ]; then
  DB=50
fi
bn=$(basename "$FILE");
path=$(dirname "$FILE");
name=$(echo "$FILE"|cut -d. -f1);
ext=$(echo "$FILE"|cut -d. -f2);
newfile="$name_plus_50.$ext"
newbn=$(basname $newfile);
db="$DB"dB
boost=$(ffmpeg -i "$FILE" -vcodec copy -af "volume=$db" $newfile);
if [ $? -eq 0 ]; then
  echo "Boosted $bn by $DB db, saved as $newbn in $path"
else
   >&2 printf "Something went wrong trying to boost with ffmpeg."
   exit 1;
fi