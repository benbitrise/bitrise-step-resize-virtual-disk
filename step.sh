#!/usr/bin/env bash
# fail if any commands fails
set -e
# make pipelines' return status equal the last command to exit with a non-zero status, or zero if all commands exit successfully
set -o pipefail
# debug log

if [[ $(uname) != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi




# Run diskutil list and capture the output
DISKUTIL_OUTPUT=$(diskutil list)

# Echo the diskutil output for reference
echo "Disk listing:"
echo "$DISKUTIL_OUTPUT"
echo "----------------------------------------"

# Find the internal physical disk
# Look for an internal physical disk with Apple_APFS container
INTERNAL_DISK=""
CONTAINER_SCHEME=""

echo "Searching for internal physical disk with APFS container..."

while IFS= read -r line; do
    # Check if it's a disk line (starts with /dev/disk)
    if [[ $line =~ ^/dev/disk([0-9]+) ]]; then
        CURRENT_DISK="disk${BASH_REMATCH[1]}"
        INTERNAL=false
        PHYSICAL=false
        CONTAINER_FOUND=false
    fi
    
    # Check if it's internal
    if [[ $line =~ "internal" ]]; then
        INTERNAL=true
    fi
    
    # Check if it's physical
    if [[ $line =~ "physical" ]]; then
        PHYSICAL=true
    fi

    # Look for Apple_APFS Container
    if [[ $line =~ Apple_APFS[[:space:]]+Container ]]; then
        CONTAINER_FOUND=true
        # Extract the partition number
        PARTITION_NUM=$(echo "$line" | awk '{print $1}' | sed 's/://')
    fi
    
    # If we have found an internal physical disk with an APFS container, remember it
    if [[ $INTERNAL == true && $PHYSICAL == true && $CONTAINER_FOUND == true ]]; then
        INTERNAL_DISK=$CURRENT_DISK
        CONTAINER_SCHEME="${INTERNAL_DISK}s${PARTITION_NUM}"
        break
    fi
done <<< "$DISKUTIL_OUTPUT"

# Check if we found an internal disk with APFS container
if [[ -z $INTERNAL_DISK || -z $CONTAINER_SCHEME ]]; then
    echo "Error: Could not find an internal physical disk with an Apple_APFS container."
    exit 1
fi

echo "Found internal physical disk: $INTERNAL_DISK"
echo "APFS Container identifier: $CONTAINER_SCHEME"

BEFORE_BYTES=$(diskutil info $CONTAINER_SCHEME | grep "Container Total Space" | awk '{print $4}' | sed 's/,//g' | sed 's/(//')

# Run the resize command
echo "----------------------------------------"
echo "Executing: diskutil apfs resizeContainer $CONTAINER_SCHEME 0"
diskutil apfs resizeContainer "$CONTAINER_SCHEME" "$space_to_claim"
echo "Resize operation completed."

AFTER_BYTES=$(diskutil info $CONTAINER_SCHEME | grep "Container Total Space" | awk '{print $4}' | sed 's/,//g' | sed 's/(//')

DIFF_BYTES=$((AFTER_BYTES - BEFORE_BYTES))
envman add --key BYTES_RECLAIMED --value "${DIFF_BYTES}"

