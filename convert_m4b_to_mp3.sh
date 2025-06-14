#!/bin/bash

HELP="\
Outputs DRM free copies of encrypted Audible AAX audiobooks in M4B 
and/or per chapter MP3 with M3U playlist. 
Retains all metadata including cover image.

Accepts unencrypted M4B (for MP3 conversion)

Requirements
============
Dependencies : ffmpeg, jq, lame, GNU Parallel
sudo apt install ffmpeg libavcodec-extra jq

Usage
=====
./${0##*/} [book.m4b] [input options] [output options]
 [input options]

 [output options] (at least --m4b or --mp3 is required)
   --dryrun          Don't output or encode anything.
                     Useful for previewing a batch job and identifying 
                     inputfiles with (some) errors.
   --m4b             M4B Audiobook format. One file with chapters & cover.
   --m4bbitrate=     Set the bitrate used by --reencode (defaults to 64k).
   --mp3             MP3 one file per-chapter with M3U.
                     Implied if passed an M4B file.
   --mp3bitrate=     Set the MP3 encode bitrate (defaults to 64k).


Example Usage
=============
Create per chapter MP3 with low bitrate from M4B file
./${0##*/} book.m4b --mp3 --mp3bitrate=32k --dryrun

For unattened batch processing (*.m4b as input) do a --dryrun and 
replace any files that show error messages if possible .. or just YOLO.


Anti-Piracy Notice
==================
Note that this project does NOT ‘crack’ the DRM. It simply allows the user
to convert their unencyrpted audiobook to mp3 format.

Please only use this application for gaining full access to your own audiobooks
for archiving/conversion/convenience. Audiobooks should not be uploaded
to open servers, torrents, or other methods of mass distribution. No help will
be given to people doing such things. Authors, retailers, and publishers all
need to make a living, so that they can continue to produce audiobooks for us
to hear, and enjoy. Don’t be a parasite.

Borrowed from https://apprenticealf.wordpress.com/
"

declare -i DRYRUN=0
declare -r FFMPEG_LOGLEVEL="-loglevel error"
declare -a INPUT_FILES=()
declare -i OUTPUT_MP3=0
declare -i CHAPTERED=1
# declare -- _BITRATE=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dryrun)
            DRYRUN=1
            shift
            ;;
        -h|--help)
            echo -e "$HELP"
            exit 1
            ;;
        -c|--chaptered)
            CHAPTERED=1
            shift
            ;;
        -nc|--nochaptered)
            CHAPTERED=0
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --mp3)
            OUTPUT_MP3=1
            OUTPUT_EXT="mp3"
            OUTPUT_CODEC="libmp3lame"
            OUTPUT_CONTAINER="mp3"
            shift
            ;;
        --bitrate)
            _BITRATE="$2"
            shift 2
            ;;
        *)
            if [[ -f "$1" ]]; then
                if [[ "$1" == *.m4b ]]; then
                    OUTPUT_MP3=1
                    INPUT_FILES+=( "$1" )
                fi
            elif [[ -d "$1" ]]; then
                # untested with directories ... 
                # or add recusion here later
                # (mwhahahahaa)
                # echo $arg;
                # while IFS= read -r -d '' file; do
                #     INPUT_FILES+=( "$file" )
                # done < <(find "$arg" -type f -name "*.m4b" -print0)
                for item in "$1"/*.m4b; do
                    INPUT_FILES+=( "$item" )
                done
                echo "- Ignoring directory '$1'"
            else
                echo -e "Unknown argument '$1'.\nTry './${0##*/} --help' for usage.\n"
                exit 1
            fi
            shift
            ;;
    esac
done


# no output set?
if [[ "$OUTPUT_MP3" == 0 ]]; then
    echo -e "No output formats specified (--m4b,--mp3)\nSee './${0##*/} --help' for usage.\n"
    exit 1
fi

# no source file?
if [[ ${#INPUT_FILES[@]} == 0 ]]; then
    echo -e "No .m4b input files specified.\nSee './${0##*/} --help' for usage.\n"
    exit 1
fi

# For testing purpose
for file in "${INPUT_FILES[@]}"
do
    echo "$file"
done

#Vroom Vrooom
for INPUT_FILE in "${INPUT_FILES[@]}"; do
    SPLIT=$SECONDS
    # temporary folder.
    WORKPATH=$(mktemp -d -t ${0##*/}-XXXXXXXXXX)
    
    if [[ -n "$_BITRATE" ]]; then
        BITRATE_KBPS=${_BITRATE}
    else
        _BITRATE_BPS=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
        BITRATE_KBPS=$(echo "scale=0; ($_BITRATE_BPS + 500) / 1000" | bc) # Add 500 for proper rounding
    fi

    # Book info
    BOOKTITLE=$(ffprobe -v quiet -show_format "$INPUT_FILE" | grep "TAG:title" | cut -d"=" -f2 | tr -d '"')
    AUTHOR=$(ffprobe -v quiet -show_format "$INPUT_FILE" | grep "TAG:artist" | cut -d"=" -f2 | tr -d '"')
    YEAR=$(ffprobe -v quiet -show_format "$INPUT_FILE" | grep "TAG:date" | cut -d"=" -f2 | tr -d '"')
    GENRE=$(ffprobe -v quiet -show_format "$INPUT_FILE" | grep "TAG:genre" | cut -d"=" -f2 | tr -d '"')
    COMMENT=$(ffprobe -v quiet -show_format "$INPUT_FILE" | grep "TAG:comment" | cut -d"=" -f2 | tr -d '"')
    ffmpeg $FFMPEG_LOGLEVEL -i "$INPUT_FILE" -f ffmetadata "$WORKPATH/metadata.txt"
    ARTIST_SORT=$(sed 's/.*=\(.*\)/\1/' <<<$(cat "$WORKPATH/metadata.txt" | grep -m 1 ^sort_artist | tr -d '"'))
    ALBUM_SORT=$(sed 's/.*=\(.*\)/\1/' <<<$(cat "$WORKPATH/metadata.txt" | grep -m 1 ^sort_album | tr -d '"'))

    # If a title begins with A, An, or The, we want to rename it so it sorts well
    TOKENWORDS=("A" "An" "The")
    FSBOOKTITLE="$BOOKTITLE"
    FSAUTHOR="$AUTHOR"
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
    FSBOOKTITLE=$(echo $FSBOOKTITLE | perl -pe 's/[<>:"\/\\\|\?\*]/-/g')
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
    if [[ "$DRYRUN" == 0 ]]; then
        DRMFREE="$WORKPATH/m4b/$FSBOOKTITLE.m4b"
        ffmpeg -loglevel error -stats -i "$INPUT_FILE" -map 0:a -c copy "$DRMFREE"
    fi
    # Dryrun referances initial file
    if [[ "$DRYRUN" == 1 ]]; then
        DRMFREE=$INPUT_FILE
    fi

    # make work file
    JOBENCODER="$WORKPATH/jobs_encode.sh"
    echo "#!/bin/bash" | tee "$JOBENCODER" 1> /dev/null
    chmod +x "$JOBENCODER"
    
    # MP3 (one track per chapter, metadata and playlist)
    if [[ "$CHAPTERED" == 1 && -z ${#ID[@]} ]]; then
        echo "- Preparing $OUTPUT_EXT Encoding Jobs"
        mkdir "$WORKPATH/$OUTPUT_EXT"
        PLAYLIST="$WORKPATH/$OUTPUT_EXT/$FSBOOKTITLE ($FSAUTHOR $YEAR).m3u"
        echo -e "#EXTM3U\n#EXTENC: UTF-8\n#EXTGENRE:$GENRE\n#EXTART:$AUTHOR\n#PLAYLIST:$BOOKTITLE ($AUTHOR $YEAR)" | tee "$PLAYLIST" 1> /dev/null
        
        for i in ${!ID[@]}
        do
            let TRACKNO=$i+1
            echo -e " ${START_TIME[$i]} - ${END_TIME[$i]}\t${TITLE[$i]}"

            # mp3 encoder job
            OUTPUT_ENCODE="_$TRACKNO.$OUTPUT_EXT"
            OUTPUT_FINAL="$(printf "%02d" $TRACKNO). $FSBOOKTITLE - ${TITLE[$i]}.$OUTPUT_EXT"
            COMMAND="set -x;echo \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
                ffmpeg $FFMPEG_LOGLEVEL -i \"${DRMFREE/"\$"/"\\\$"}\" -vn \
                -ss ${START_TIME[$i]} -to ${END_TIME[$i]} \
                -map_chapters -1 \
                -id3v2_version 4 \
                -metadata title=\"${TITLE[$i]}\" \
                -metadata track=\"$TRACKNO/${#ID[@]}\" \
                -metadata album=\"$BOOKTITLE\" \
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

            # m3u line
            BEGSECS=$( echo "${START_TIME[$i]}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' )
            ENDSECS=$( echo "${END_TIME[$i]}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' )
            LENGTH=$( echo "scale=0;($ENDSECS-$BEGSECS+0.5)/1" | bc )
            echo "#EXTINF: $LENGTH, $FSBOOKTITLE - ${TITLE[$i]}" | tee -a "$PLAYLIST" 1> /dev/null
            echo "${OUTPUT_FINAL/"\$"/"\\\$"}" | tee -a "$PLAYLIST" 1> /dev/null
        done
        
        echo -e "- Encoding:"
        if [[ "$DRYRUN" == 0 ]]; then
            (exec "$JOBENCODER")
            (exec "$JOBCOVER")
        fi
        if [[ "$DRYRUN" == 1 ]]; then
            echo -e " Or Not! --dryrun specified, nothing to do."
        fi
    else
        echo "- Preparing $OUTPUT_EXT Encoding Job"
        mkdir "$WORKPATH/$OUTPUT_EXT"

        let TRACKNO=1
        OUTPUT_ENCODE="_$TRACKNO.$OUTPUT_EXT"
        OUTPUT_FINAL="$FSBOOKTITLE - ${TITLE[$i]}.$OUTPUT_EXT"
        COMMAND="set -x; echo \"$WORKPATH/$OUTPUT_EXT/$OUTPUT_ENCODE\" && \
            ffmpeg $FFMPEG_LOGLEVEL -i \"${DRMFREE/"\$"/"\\\$"}\" -vn \
            -map_chapters -1 \
            -id3v2_version 4 \
            -metadata album=\"$BOOKTITLE\" \
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
        if [[ "$DRYRUN" == 0 ]]; then
            (exec "$JOBENCODER")
            (exec "$JOBCOVER")
        fi
        if [[ "$DRYRUN" == 1 ]]; then
            echo -e " Or Not! --dryrun specified, nothing to do."
        fi

    fi

    # clean up
    rm "$JOBENCODER"
    rm "$JOBCOVER"
    if [[ "$DRYRUN" == 0 ]]; then
        if [[ -n "$OUTPUT_EXT" ]]; then
            mkdir "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -p
            cp $COVERIMG "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -f
            cp $WORKPATH/$OUTPUT_EXT/* "$(dirname "$INPUT_FILE")/$OUTPUT_EXT/" -f
        fi
    fi
    rm -r "$WORKPATH"
    # loop process time
    SPLIT_RUN=$(($SECONDS-$SPLIT))
    echo -e "- Done. processed in $(($SPLIT_RUN / 3600))hrs $((($SPLIT_RUN / 60) % 60))min $(($SPLIT_RUN % 60))sec.\n"
done

# total time if more than one
if [[ ${#INPUT_FILES[@]} -gt "1" ]]; then
    echo -e "\nDone processing ${#INPUT_FILES[@]} file(s) in $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec."
fi