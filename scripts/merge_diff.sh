#!/bin/bash

set -euo pipefail

# Check if a directory was provided as argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <target_directory> [output_name]"
  exit 1
fi

TARGET_DIR="${1%/}"

# Verify that the directory actually exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory '$TARGET_DIR' not found."
  exit 1
fi

# Find the first patch file to clone its extension
FIRST_PATCH=$(find "$TARGET_DIR" -type f \( -name "*.diff" -o -name "*.patch" \) | head -n 1)

if [ -z "$FIRST_PATCH" ]; then
  echo "Error: No .diff or .patch files found in '$TARGET_DIR'."
  exit 1
fi

EXT="${FIRST_PATCH##*.}"

# Determine the output filename based on the second argument
if [ $# -ge 2 ]; then
  OUTPUT_PATCH="$2"
  # Only append the extension if the user didn't specify any extension at all (no dot in the name)
  if [[ $OUTPUT_PATCH != *.* ]]; then
    OUTPUT_PATCH="${OUTPUT_PATCH}.${EXT}"
  fi
else
  OUTPUT_PATCH="${TARGET_DIR}_combined.${EXT}"
fi

echo "Combining patches from '$TARGET_DIR' into '$OUTPUT_PATCH'..."

# Clear the output file if it already exists
> "$OUTPUT_PATCH"

# Process each file, fix its headers on the fly, and append it to the final patch
find "$TARGET_DIR" -type f -name "*.${EXT}" | sort | while read -r current_patch; do
  # Add a clean newline before each patch block to prevent syntax merging issues
  echo "" >> "$OUTPUT_PATCH"

  # Read the patch, fix the paths to include the root directory, and append
  sed -E "s|^(--- \|\+\+\+ )([ab]/)|\1\2${TARGET_DIR}/|g" "$current_patch" >> "$OUTPUT_PATCH"
done

echo "Done! Generated $OUTPUT_PATCH"
