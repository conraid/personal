#!/bin/bash

set -euo pipefail

# Check if a patch file was provided as argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <patchfile>"
  exit 1
fi

PATCHFILE="$1"

# Verify that the file actually exists
if [ ! -f "$PATCHFILE" ]; then
  echo "Error: File '$PATCHFILE' not found."
  exit 1
fi

# Extract the extension from the input file (defaults to diff if none found)
EXT="${PATCHFILE##*.}"
if [ "$EXT" = "$PATCHFILE" ]; then
  EXT="diff"
fi

# Get the very first file path from lsdiff to determine the original root directory
FIRST_ENTRY=$(lsdiff "$PATCHFILE" | head -n 1)

# Extract the original root directory name (everything before the first slash)
ORIG_ROOT=$(echo "$FIRST_ENTRY" | cut -d'/' -f1)

# Clean the root directory name by removing rc, beta or alpha suffixes (e.g., tiger-3.2.4~rc1 -> tiger-3.2.4)
CLEAN_ROOT=$(echo "$ORIG_ROOT" | sed -E 's|~rc[0-9]+||g; s|-rc[0-9]+||g; s|~beta[0-9]+||g; s|~alpha[0-9]+||g')

# Extract individual patches and recreate the directory structure inside the clean root
for f in $(lsdiff "$PATCHFILE"); do
  # Dynamically strip the original first level directory
  percorso_relativo=$(echo "$f" | sed -E 's|^[^/]+/(.*)|\1|')

  # Target path including the new clean root directory
  target_path="${CLEAN_ROOT}/${percorso_relativo}"

  # Get the directory path only
  directory_dest=$(dirname "$target_path")

  # Create the target directory tree if it does not exist
  mkdir -p "$directory_dest"

  # Extract the specific patch and save it with the original extension
  filterdiff -i "$f" "$PATCHFILE" > "${target_path}.${EXT}"
done
