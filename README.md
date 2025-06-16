# M4B Audiobook Converter

This script converts unencrypted M4B audiobooks into chapterized MP3 files with an M3U playlist. It can also output a DRM-free M4B copy. The script aims to retain all metadata, including the cover image.

## Features

- Converts unencrypted `.m4b` files into:
  - Per-chapter `.mp3` files with `.m3u` playlists
- Retains cover images and metadata
- Customizable bitrate
- `--dryrun` mode for safe previews
- Supports individual files and batch conversion

## Requirements

*   `ffmpeg` 
*   `jq` (for parsing chapter metadata)

On Debian/Ubuntu systems, these can typically be installed with:
```bash
sudo apt install ffmpeg jq
```

## Usage

Save the script to a file (e.g., `convert_audiobook.sh`) and make it executable (`chmod +x convert_audiobook.sh`).

```bash
./convert_audiobook.sh [book.m4b | directory | file] [options]
```

**Input:**
*   `[input.m4b]`: Path to the source M4B audiobook file. Multiple M4B files can be specified.

**Output Options (output format option, like `--format mp3` or `--format m4b`, defaults to mp3 when not provided):**

*   `--format <value>`: Takes a parameter (e.g., `mp3`, `m4b`). Defaults to `mp3` when not provided.
*   `--bitrate <value>`: Set the MP3 encoding bitrate (e.g., `128k`, `192k`). Defaults to same as source file.
*   `--dryrun`: Preview the operations, showing what would be done without actually creating files or encoding.
*   `-h`, `--help`: Display the built-in help message and exit.

**Examples:**

1.  Convert a single M4B file to per-chapter MP3s at a 128kbps bitrate:
    ```bash
    ./convert_audiobook.sh "My Awesome Book.m4b" --format mp3 --bitrate 128k
    ```

2.  Process multiple M4B files, creating MP3s with the default bitrate, and perform a dry run:
    ```bash
    ./convert_audiobook.sh "Book One.m4b" "Another Story.m4b" --format mp3 --dryrun
    ```

## Anti-Piracy Notice

Note that this project allows the user to convert their unencrypted M4B audiobooks to MP3 format.

Please only use this application for gaining full access to your own audiobooks for archiving/conversion/convenience. Audiobooks should not be uploaded to open servers, torrents, or other methods of mass distribution. No help will be given to people doing such things. Authors, retailers, and publishers all need to make a living, so that they can continue to produce audiobooks for us to hear, and enjoy. Don’t be a parasite.