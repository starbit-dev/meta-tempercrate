#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# build_tempercrate_image.sh
#
# Build a raw SD card image for a selected TemperCrate Yocto image by using the
# corresponding pre-generated FlashLayout TSV file deployed by BitBake.
#
# Supported images:
#   - tempercrate-image-core
#   - tempercrate-image-debug
#
# The script:
#   1. Detects the current Yocto build directory
#   2. Reads MACHINE from conf/local.conf
#   3. Selects the proper FlashLayout TSV according to the requested image
#   4. Copies create_tempercrate_sdcard_image.sh into the deploy/scripts directory
#   5. Invokes it to generate the raw SD card image
#   6. Renames the generated RAW file to an image-specific filename
#
# Expected deployed TSV files:
#   - flashlayout_tempercrate-image-core/optee/FlashLayout_TemperCrate_Core.tsv
#   - flashlayout_tempercrate-image-debug/optee/FlashLayout_TemperCrate_Debug.tsv
#
# Usage:
#   ./build_tempercrate_image.sh tempercrate-image-core
#   ./build_tempercrate_image.sh tempercrate-image-debug
#
# Optional environment variable:
#   SDCARD_SIZE=2500
# -----------------------------------------------------------------------------

#set -euo pipefail

SDCARD_SIZE="${SDCARD_SIZE:-2200}"

usage() {
    echo "Usage: $0 <image-name>"
    echo
    echo "Supported image names:"
    echo "  tempercrate-image-core"
    echo "  tempercrate-image-debug"
    echo
    echo "Example:"
    echo "  $0 tempercrate-image-debug"
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

IMAGE_NAME="$1"

case "$IMAGE_NAME" in
    tempercrate-image-core)
        FLASHLAYOUT_FILENAME="FlashLayout_TemperCrate_Core.tsv"
        OUTPUT_RAW_BASENAME="tempercrate-image-core-sdcard.raw"
        IMAGE_FILE_NAME="FlashLayout_TemperCrate_Core.raw"
        ;;
    tempercrate-image-debug)
        FLASHLAYOUT_FILENAME="FlashLayout_TemperCrate_Debug.tsv"
        OUTPUT_RAW_BASENAME="tempercrate-image-debug-sdcard.raw"
        IMAGE_FILE_NAME="FlashLayout_TemperCrate_Debug.raw"
        ;;
    *)
        echo "ERROR: unsupported image name: $IMAGE_NAME"
        echo
        usage
        ;;
esac

# Must be executed from a Yocto build directory
if [ ! -f "conf/local.conf" ]; then
    echo "ERROR: this script must be run from a Yocto build directory."
    echo "Missing file: conf/local.conf"
    echo
    echo "Example:"
    echo "  cd /path/to/build-directory"
    echo "  ../layers/meta-tempercrate/meta-tempercrate-os/scripts/build_tempercrate_image.sh $IMAGE_NAME"
    exit 1
fi

BUILD_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MACHINE="$(sed -n 's/^MACHINE[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' conf/local.conf | tail -n1)"

if [ -z "$MACHINE" ]; then
    echo "ERROR: unable to determine MACHINE from conf/local.conf"
    exit 1
fi

DEPLOY_DIR="$BUILD_DIR/tmp-glibc/deploy/images/$MACHINE"
DEPLOY_SCRIPTS_DIR="$DEPLOY_DIR/scripts"

SOURCE_SCRIPT="$SCRIPT_DIR/create_tempercrate_sdcard_image.sh"
TARGET_SCRIPT="$DEPLOY_SCRIPTS_DIR/create_tempercrate_sdcard_image.sh"

FLASHLAYOUT_DIR="$DEPLOY_DIR/flashlayout_${IMAGE_NAME}/optee"
FLASHLAYOUT_TSV="$FLASHLAYOUT_DIR/$FLASHLAYOUT_FILENAME"
FLASHLAYOUT_REL="../flashlayout_${IMAGE_NAME}/optee/$FLASHLAYOUT_FILENAME"

FINAL_RAW_PATH="$DEPLOY_DIR/$OUTPUT_RAW_BASENAME"

echo "------------------------------------------------------------"
echo "TemperCrate SD card image builder"
echo "------------------------------------------------------------"
echo "Build directory     : $BUILD_DIR"
echo "Machine             : $MACHINE"
echo "Image name          : $IMAGE_NAME"
echo "Deploy directory    : $DEPLOY_DIR"
echo "FlashLayout TSV     : $FLASHLAYOUT_TSV"
echo "Output RAW file     : $IMAGE_FILE_NAME"
echo "SD card size (MB)   : $SDCARD_SIZE"
echo "------------------------------------------------------------"
echo

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "ERROR: deploy directory not found:"
    echo "  $DEPLOY_DIR"
    echo
    echo "Did you already run:"
    echo "  bitbake $IMAGE_NAME"
    exit 1
fi

if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "ERROR: helper script not found:"
    echo "  $SOURCE_SCRIPT"
    exit 1
fi

if [ ! -f "$FLASHLAYOUT_TSV" ]; then
    echo "ERROR: FlashLayout TSV not found:"
    echo "  $FLASHLAYOUT_TSV"
    echo
    echo "Make sure the image has been built and the corresponding TSV"
    echo "has been deployed with the expected name."
    exit 1
fi

mkdir -p "$DEPLOY_SCRIPTS_DIR"

#echo "Copying helper script to deploy/scripts..."
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"
echo "Generating raw SD card image with command ./create_tempercrate_sdcard_image.sh $FLASHLAYOUT_REL"
echo "########################################################################"
cd "$DEPLOY_SCRIPTS_DIR"
SDCARD_SIZE="$SDCARD_SIZE" ./create_tempercrate_sdcard_image.sh "$FLASHLAYOUT_REL"
echo "########################################################################"

if [ $? -eq 0 ]; then
    echo "Raw image generated with success"
else
    echo "ERROR Failed to generate EAW image ==> Exit with Failure"
    exit 1
fi

GENERATED_RAW="$(find "$DEPLOY_DIR" -maxdepth 1 -type f -name "*.raw" ! -name "$OUTPUT_RAW_BASENAME" | head -n1)"

if [ -z "$GENERATED_RAW" ]; then
    echo "ERROR: no generated RAW file found in:"
    echo "  $DEPLOY_DIR"
    exit 1
fi

FINAL_RAW_PATH="$DEPLOY_DIR/$OUTPUT_RAW_BASENAME/$GENERATED_RAW"
#echo
#echo "Raw SD card image generation completed successfully."
#echo "Final output:"
#echo "  $FINAL_RAW_PATH"
echo "You can flash image using following commands"
echo "cd $DEPLOY_DIR"
echo "sudo dd if=$IMAGE_FILE_NAME of=/dev/sdb bs=8M conv=fdatasync status=progress"