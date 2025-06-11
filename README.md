# M4B Audiobook Converter

This script converts unencrypted M4B audiobooks into chapterized MP3 files with an M3U playlist. It can also output a DRM-free M4B copy. The script aims to retain all metadata, including the cover image.

## Features

*   Converts M4B files to per-chapter MP3s.
*   Generates an M3U playlist for MP3 chapters.
*   Preserves metadata: title, author, year, genre, comments, and cover art.
*   Organizes output into a folder named after the book title.
*   Sanitizes filenames for better sorting and compatibility.
*   Supports custom bitrate for MP3 encoding.
*   Dry-run mode to preview operations without modifying files.

## Requirements

*   `ffmpeg` (and `libavcodec-extra` for extended codec support)
*   `jq` (for parsing chapter metadata)
*   `lame` (for MP3 encoding via `libmp3lame`)

On Debian/Ubuntu systems, these can typically be installed with:
```bash
sudo apt install ffmpeg libavcodec-extra jq lame
```

## Usage

Save the script to a file (e.g., `convert_audiobook.sh`) and make it executable (`chmod +x convert_audiobook.sh`).

```bash
./convert_audiobook.sh [input.m4b] [options]
```

**Input:**
*   `[input.m4b]`: Path to the source M4B audiobook file. Multiple M4B files can be specified.

**Output Options (at least one output format option, like `--mp3` or `--m4b`, is generally expected):**

*   `--mp3`: Output MP3 files, one per chapter, along with an M3U playlist. This is also the default action if an M4B file is provided as input without other specific output format flags.
*   `--bitrate=<value>`: Set the MP3 encoding bitrate (e.g., `128k`, `192k`). Defaults to `192k`
*   `--dryrun`: Preview the operations, showing what would be done without actually creating files or encoding.
*   `-h`, `--help`: Display the built-in help message and exit.

**Examples:**

1.  Convert a single M4B file to per-chapter MP3s at a 128kbps bitrate:
    ```bash
    ./convert_audiobook.sh "My Awesome Book.m4b" --mp3 --bitrate=128k
    ```

2.  Process multiple M4B files, creating MP3s with the default bitrate, and perform a dry run:
    ```bash
    ./convert_audiobook.sh "Book One.m4b" "Another Story.m4b" --mp3 --dryrun
    ```

## Anti-Piracy Notice

Note that this project does NOT ‘crack’ the DRM. It simply allows the user to convert their unencrypted M4B audiobooks to MP3 format.

Please only use this application for gaining full access to your own audiobooks for archiving/conversion/convenience. Audiobooks should not be uploaded to open servers, torrents, or other methods of mass distribution. No help will be given to people doing such things. Authors, retailers, and publishers all need to make a living, so that they can continue to produce audiobooks for us to hear, and enjoy. Don’t be a parasite.

(Notice borrowed from https://apprenticealf.wordpress.com/)