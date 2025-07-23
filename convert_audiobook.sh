#!/bin/bash

HELP="\
Outputs audiobooks in M4B and/or per-chapter MP3 format with M3U playlist. 
Retains all metadata, including cover image.

Accepts unencrypted M4B files (for MP3 conversion).

Requirements
============
Dependencies: ffmpeg, jq, lame
Install with: sudo apt install ffmpeg jq

Usage
=====
./${0##*/} [book.m4b | directory | file] [options]

Options:
  --dryrun           Don't output or encode anything.
                     Useful for previewing a batch job and identifying 
                     input files with potential issues.

  --format           Output format of audiobook (file & cover).
                     [mp3] Output MP3 files (one per chapter, with M3U playlist).
                        Implied if passed an M4B file.
  --bitrate BIT      Set encode bitrate (default: 64k).

  -h, --help         Show this help message and exit.

Example
=======
Convert M4B to per-chapter MP3 at 64k bitrate:
  ./${0##*/} book.m4b --format mp3 --bitrate 64k --dryrun

Batch convert all .m4b files in current directory (with dry run):
  ./${0##*/} . --format mp3 --dryrun

Anti-Piracy Notice
==================
This script does NOT bypass DRM. It only converts *your own* unencrypted audiobooks 
to other formats for backup or personal use.

Please do not use this script to redistribute audiobooks. Support authors, narrators, 
and publishers by respecting copyright and licensing terms.
"


declare -i DRYRUN=0
declare -i DEBUG=0
declare -a INPUT_FILES=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dryrun)
            DRYRUN=1
            shift
            ;;
        -o|--format)
            FORMAT="$2"
            shift 2
            ;;
        --bitrate)
            _BITRATE="$2"
            shift 2
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        -h|--help)
            echo -e "$HELP"
            exit 1
            ;;
        *)
            INPUT_FILES+=("$1")
            shift
            ;;
    esac
done

if [ "$DEBUG" -eq 1 ]; then
    echo "Debugging info starts here"
    set -x
    declare -r FFMPEG_LOGLEVEL="-loglevel debug"
else
    declare -r FFMPEG_LOGLEVEL="-loglevel error"
fi

# Set variables based on FORMAT
FORMAT="${FORMAT:-mp3}"
case "$FORMAT" in
    mp3)
        OUTPUT_EXT="mp3"
        OUTPUT_CODEC="libmp3lame"
        OUTPUT_CONTAINER="mp3"
        shift
        ;;
    m4b)
        OUTPUT_EXT="m4b"
        OUTPUT_CODEC="copy"
        OUTPUT_CONTAINER="mp4"
        shift
        ;;
    *)
        echo "Unsupported format: $FORMAT\nSee './${0##*/} --help' for usage.\n"
        exit 1
        ;;
esac

# Process each file or expand dirs
EXPANDED_FILES=()
for src in "${INPUT_FILES[@]}"; do
    if [ -d "$src" ]; then
        for f in "$src"/*.m4b; do 
            [ -f "$f" ] && EXPANDED_FILES+=("$f")
        done
    elif [ "$src" == *'*'* ]; then
        for f in $src; do
            [ -f "$f" ] && EXPANDED_FILES+=("$f")
        done
    elif [ -f "$src" ]; then
        EXPANDED_FILES+=("$src")
    else
        echo "Warning: Skipping invalid input '$src'" >&2
    fi
done

INPUT_FILES=("${EXPANDED_FILES[@]}")
[ ${#INPUT_FILES[@]} -ge 1 ] || {
    echo "No valid input files found."
    exit 1
}

cleanup() {
    if [ -n "$WORKPATH" ] && [ -d "$WORKPATH" ]; then
        echo "- Cleaning up temp files..."
        rm -rf "$WORKPATH"
    fi
}
trap cleanup EXIT INT HUP TERM

get_metadata() {
    ffprobe -v quiet -show_format "$1" \
    | sed -n 's/^TAG:'"$2"'=\(.*\)$/\1/p';
}

# Main
for INPUT_FILE in "${INPUT_FILES[@]}"; do
    SPLIT=$SECONDS
    # temporary folder.
    WORKPATH=$(mktemp -d -t ${0##*/}-XXXXXXXXXX)
    trap cleanup EXIT INT HUP TERM
    
    # Compute bitrate if not set
    if [ -n "$_BITRATE" ]; then
        BITRATE_KBPS=${_BITRATE/k/}
    else
        _BITRATE_BPS=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
        BITRATE_KBPS=$(echo "scale=0; ($_BITRATE_BPS + 500) / 1000" | bc) # Add 500 for proper rounding
    fi

    # Book info
    BOOKTITLE=$(get_metadata "$INPUT_FILE" title)
    AUTHOR=$(get_metadata "$INPUT_FILE" artist)
    ALBUM=$(get_metadata "$INPUT_FILE" album)
    YEAR=$(get_metadata "$INPUT_FILE" date)
    GENRE=$(get_metadata "$INPUT_FILE" genre)
    COMMENT=$(get_metadata "$INPUT_FILE" comment)
    
    ffmpeg $FFMPEG_LOGLEVEL -i "$INPUT_FILE" -f ffmetadata "$WORKPATH/metadata.txt"
    ARTIST_SORT=$(sed 's/.*=\(.*\)/\1/' <<<$(cat "$WORKPATH/metadata.txt" | grep -m 1 ^sort_artist | tr -d '"'))
    ALBUM_SORT=$(sed 's/.*=\(.*\)/\1/' <<<$(cat "$WORKPATH/metadata.txt" | grep -m 1 ^sort_album | tr -d '"'))

    FSBOOKTITLE="$BOOKTITLE"
    FSAUTHOR="$AUTHOR"

    # If a title begins with A, An, or The, we want to rename it so it sorts well
    TOKENWORDS=("A" "An" "The")
    for i in "${TOKENWORDS[@]}"; do
        if [[ "$FSBOOKTITLE" == "$i "* ]]; then
            FSBOOKTITLE=$(echo $FSBOOKTITLE | perl -pe "s/^$i //")
            # If book has a subtitle, we want the token word to go right before it
            if [[ "$FSBOOKTITLE" == *": "* ]]; then
                FSBOOKTITLE=$(echo $FSBOOKTITLE | perl -pe "s/: /, $i: /")
                break  
            fi
            FSBOOKTITLE="$FSBOOKTITLE, $i"
            break
        fi
    done

    # Replace special characters in Book Title and Author Name with a - to make
    # them file name safe.
    FSBOOKTITLE=$(echo $FSBOOKTITLE | perl -pe 's/[<>:"\/\\\|\?\*]/-/g' | sed -E 's/ +/ /g; s/^ *| *$//g')
    FSAUTHOR=$(echo $FSAUTHOR | perl -pe 's/[<>:"\/\\\|\?\*]/-/g')

    # chapters
    ffprobe $FFMPEG_LOGLEVEL -i "$INPUT_FILE" -print_format json -show_chapters -loglevel error -sexagesimal > "$WORKPATH/chapters.json"
    readarray -t ID <<< $(jq -r '.chapters[].id' "$WORKPATH/chapters.json")
    readarray -t START_TIME <<< $(jq -r '.chapters[].start_time' "$WORKPATH/chapters.json")
    readarray -t END_TIME <<< $(jq -r '.chapters[].end_time' "$WORKPATH/chapters.json")
    readarray -t TITLE <<< $(jq -r '.chapters[].tags.title' "$WORKPATH/chapters.json" | tr -d '"')

    # Echo title (author) - runtime
    echo "$FSBOOKTITLE ($FSAUTHOR) - ${END_TIME[-1]}"

    # extract cover image
    COVERIMG=$WORKPATH/cover.png
    echo "- Extracting Cover Image"
    JOBCOVER="$WORKPATH/jobs_covers.sh"
    echo "#!/bin/bash" | tee "$JOBCOVER" 1> /dev/null
    chmod +x "$JOBCOVER"
    ffmpeg $FFMPEG_LOGLEVEL -y -i "$INPUT_FILE" -frames:v 1 "$COVERIMG"

    # M4B (direct copy with all metadata sans encryption - cover retained from original file)
    # use this as the source file from here on out
    mkdir "$WORKPATH/m4b"
    echo "- Creating \"$FSBOOKTITLE.m4b\""
    if [ "$DRYRUN" == 0 ]; then
        WORKINGCOPY="$WORKPATH/m4b/$FSBOOKTITLE.m4b"
        ffmpeg -loglevel error -stats -i "$INPUT_FILE" -map 0:a -c copy "$WORKINGCOPY"
    fi
    # Dryrun referances initial file
    if [ "$DRYRUN" == 1 ]; then
        WORKINGCOPY=$INPUT_FILE
    fi

    # make work file
    JOBENCODER="$WORKPATH/jobs_encode.sh"
    echo "#!/bin/bash" | tee "$JOBENCODER" 1> /dev/null
    chmod +x "$JOBENCODER"
    
    # MP3 (one track per chapter, metadata and playlist)
    if [ ${#ID} -gt 0 ]; then
        echo "- Preparing $OUTPUT_EXT Encoding Jobs"
        mkdir "$WORKPATH/$OUTPUT_EXT"
        PLAYLIST="$WORKPATH/$OUTPUT_EXT/$FSBOOKTITLE ($FSAUTHOR $YEAR).m3u"
        echo -e "#EXTM3U\n#EXTENC: UTF-8\n#EXTGENRE:$GENRE\n#EXTART:$AUTHOR\n#PLAYLIST:$BOOKTITLE ($AUTHOR $YEAR)" | tee "$PLAYLIST" 1> /dev/null
        
        for i in ${!ID[@]}
        do
            let TRACKNO=$i+1
            TITLE[$i]=$(echo "${TITLE[$i]}" | sed -E 's/ +/ /g; s/^ *| *$//g')
            echo -e " ${START_TIME[$i]} - ${END_TIME[$i]}\t${TITLE[$i]}"

            # Encoder job
            OUTPUT_ENCODE="_$TRACKNO.$OUTPUT_EXT"
            OUTPUT_FINAL="$(printf "%02d" $TRACKNO). $FSBOOKTITLE - ${TITLE[$i]}.$OUTPUT_EXT"
            COMMAND="echo \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
                ffmpeg $FFMPEG_LOGLEVEL -i \"${WORKINGCOPY/"\$"/"\\\$"}\" -vn \
                -ss ${START_TIME[$i]} -to ${END_TIME[$i]} \
                -map_chapters -1 \
                -id3v2_version 4 \
                -metadata title=\"${TITLE[$i]}\" \
                -metadata track=\"$TRACKNO/${#ID[@]}\" \
                -metadata album=\"$ALBUM\" \
                -metadata genre=\"$GENRE\" \
                -metadata artist=\"$AUTHOR\" \
                -metadata album_artist=\"$AUTHOR\" \
                -metadata date=\"$YEAR\" \
                -metadata Comment=\"$COMMENT\" \
                -metadata album-sort=\"$ALBUM_SORT\"
                -metadata artist-sort=\"$ARTIST_SORT\"
                -codec:a $OUTPUT_CODEC \
                -b:a \"${BITRATE_KBPS}k\" \
                -f $OUTPUT_CONTAINER \
                \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\""
            echo -e $COMMAND | tee -a "$JOBENCODER" 1> /dev/null

            # Cover job (set final filename here too)
            COMMAND="echo \"Setting cover for $WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
                ffmpeg $FFMPEG_LOGLEVEL -i \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" -i \"$COVERIMG\" \
                -c copy -map 0 -map 1 \
                -metadata:s:v title=\"Album cover\" \
                -metadata:s:v comment=\"Cover (Front)\" \
                \"$WORKPATH/$OUTPUT_EXT/${OUTPUT_FINAL/"\$"/"\\\$"}\" && \
                rm \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\""
            echo -e $COMMAND | tee -a "$JOBCOVER" 1> /dev/null

            # m3u line
            BEGSECS=$( echo "${START_TIME[$i]}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' )
            ENDSECS=$( echo "${END_TIME[$i]}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' )
            LENGTH=$( echo "scale=0;($ENDSECS-$BEGSECS+0.5)/1" | bc )
            echo "#EXTINF: $LENGTH, $FSBOOKTITLE - ${TITLE[$i]}" | tee -a "$PLAYLIST" 1> /dev/null
            echo "${OUTPUT_FINAL/"\$"/"\\\$"}" | tee -a "$PLAYLIST" 1> /dev/null
        done
        
        echo -e "- Encoding:"
        if [ "$DRYRUN" == 0 ]; then
            (exec "$JOBENCODER")
            (exec "$JOBCOVER")
        fi
    else
        echo "- Preparing $OUTPUT_EXT Encoding Job"
        mkdir "$WORKPATH/$OUTPUT_EXT"

        TRACKNO=$(get_metadata "$INPUT_FILE" track | cut -d'/' -f1)
        OUTPUT_ENCODE="_$TRACKNO.$OUTPUT_EXT"
        OUTPUT_FINAL="$(printf "%02d" $TRACKNO). $FSBOOKTITLE.$OUTPUT_EXT"
        COMMAND="echo \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
            ffmpeg $FFMPEG_LOGLEVEL -i \"${WORKINGCOPY/"\$"/"\\\$"}\" -vn \
            -map_chapters -1 \
            -id3v2_version 4 \
            -metadata album=\"$ALBUM\" \
            -metadata genre=\"$GENRE\" \
            -metadata artist=\"$AUTHOR\" \
            -metadata album_artist=\"$AUTHOR\" \
            -metadata date=\"$YEAR\" \
            -metadata Comment=\"$COMMENT\" \
            -metadata album-sort=\"$ALBUM_SORT\"
            -metadata artist-sort=\"$ARTIST_SORT\"
            -codec:a $OUTPUT_CODEC \
            -b:a \"${BITRATE_KBPS}k\" \
            -f $OUTPUT_CONTAINER \
            \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\""
            echo -e $COMMAND | tee -a "$JOBENCODER" 1> /dev/null

        # cover job (set final filename here too)
        COMMAND="echo \"Setting cover for $WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
            ffmpeg $FFMPEG_LOGLEVEL -i \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" -i \"$COVERIMG\" \
            -c copy -map 0 -map 1 \
            -metadata:s:v title=\"Album cover\" \
            -metadata:s:v comment=\"Cover (Front)\" \
            \"$WORKPATH/$OUTPUT_EXT/${OUTPUT_FINAL/"\$"/"\\\$"}\" && \
            rm \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\""
        echo -e $COMMAND | tee -a "$JOBCOVER" 1> /dev/null

        echo -e "- Encoding:"
        if [ "$DRYRUN" == 0 ]; then
            (exec "$JOBENCODER")
            (exec "$JOBCOVER")
        fi
    fi

    # clean up    
    if [ "$DRYRUN" -eq 0 ]; then
        mkdir "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -p
        cp $COVERIMG "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -f
        cp $WORKPATH/$OUTPUT_EXT/* "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -f
        cp "$WORKPATH/$OUTPUT_EXT"/* "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -f
        cleanup
    else
        echo "[Dry Run] Would run:"
        cat "$JOBENCODER" "$JOBCOVER"
        cleanup
    fi

    # loop process time
    SPLIT_RUN=$(($SECONDS-$SPLIT))
    echo -e "- Done. Processed in $(($SPLIT_RUN / 3600))hrs $((($SPLIT_RUN / 60) % 60))min $(($SPLIT_RUN % 60))sec.\n"
done

# total time if more than one
if [ ${#INPUT_FILES[@]} -ge 1 ]; then
    echo -e "\nDone processing ${#INPUT_FILES[@]} file(s) in $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec."
fi