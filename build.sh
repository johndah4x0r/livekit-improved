#!/bin/bash

# Linux Live Kit Improved v1.0
# Original version: Linux Live Kit version 7
# Modified/improved by: @johndah4x0r [terencedoesmc12 AT gmail DOT com]

# Environment path
export PATH="${PATH}:.:./tools:../tools"

# Data and variables
LLKIM_LIB_1="./llkim_libs/livekitlib.stock"
LLKIM_LIB_2="./llkim_libs/livekitlib.overlayfs"
CONFIG="./.config"

LLKIM_LIB="./livekitlib"

source "$CONFIG" || exit 1
source "$LLKIM_LIB_1"|| exit 1

# only root can continue, because only root can
# read all files from your system
allow_only_root

# Change directory to build environment
CHANGEDIR="$(dirname "$0")"
echo "Changing current directory to '$CHANGEDIR'"
CWD="$(pwd)"
cd "$CHANGEDIR"

# Parse 'UNIFS' variable in .config
# HELP: 'UNIFS'; variable to choose between
case "$UNIFS" in
    'aufs' | 'AUFS')
        cp "$LLKIM_LIB_1" "$LLKIM_LIB"
        cp "./initramfs/init.stock" "./initramfs/init"

        ;;
    'overlay' | 'overlayfs' | 'OverlayFS')
        cp "$LLKIM_LIB_2" "$LLKIM_LIB"
        cp "./initramfs/init.overlayfs" "./initramfs/init"
        ;;
    *)
        echo_err "Unsupported filesystem type: $UNIFS"
        exit 1
        ;;
esac

# Re-source livekitlib
source "$LLKIM_LIB" || exit 1

# It's building time!
clear

echo_sign "BUILD SCRIPT"
echo_livekit_msg "build: Doing a self-check..."

# Check for tools
## Start with 0 errors
ERRS=0

# Check if mksquashfs exists
if ! command -v mksquashfs >/dev/null 2>&1; then
    echo_err "build: 'mksquashfs': Not found"
    (( ERRS+=1 ))
elif ! (mksquashfs 2>&1 | grep -q "Xdict-size"); then
    echo_err "build: 'mksquashfs': Not supported"
    (( ERRS+=1 ))
else
    echo_livekit_msg "build: 'mksquashfs': Found & supported"
fi

# Check if either 'mkisofs' or 'genisoimage' exists
MKISOFS="$(which mkisofs 2>/dev/null || which genisoimage 2>/dev/null)"
if [ -z "$MKISOFS" ]; then
    echo_warn "build: '\$MKISOFS': Not found"

    # Substitute $MKISOFS with `false`
    MKISOFS="false"
else
    echo_livekit_msg "build: '\$MKISOFS': $(basename "$MKISOFS")"
fi

# Check if we have 'zip'
ZIP_CMD="$(which zip 2>/dev/null)"
if [ -z "$ZIP_CMD" ]; then
    # Zip archive is the bare needs for a successful build
    echo_err "build: 'zip': not-avail"
    echo_err "build: 'zip': Critically needed!"
    (( ERRS+=2 ))
else
    echo_livekit_msg "build: 'zip': avail"
fi


if [ $ERRS -eq 0 ]; then
    echo_livekit_msg "build: Problems found: $ERRS"
    echo_livekit_msg "build: Self-check passed."
else
    echo_err "build: Problems found: $ERRS"
    echo_err "build: Self-check failed!"
    echo_err "build: Please make sure that you have all needed packages installed!"
    exit 1
fi

echo_livekit_msg "build: Preparing to build..."
clear

echo " ==========================================="
echo "  Live Kit Improved v1.0"
echo " ==========================================="
echo " System info:"
echo "  + Kernel version: $KERNEL"
echo "  + Architecture: $ARCH"
echo "  + Live Kit name: $LIVEKITNAME"
echo "  + Bundle extension: '.$BEXT'"
echo "  + Unification FS: $UNIFS"

read -r -p "Press Enter to continue or press Ctrl-C to cancel... " >/dev/null

# It's time to rock 'n roll!
clear

# Generate initramfs image (cpio-xz archive)
echo_livekit_msg "build: Generating initramfs..."

cd initramfs
INITRAMFS="$(./gen-initramfs "$LIVEKITNAME")"
cd ..

# Prepare the Live Kit archive
rm -Rf "$LIVEKITDATA"
echo_livekit_msg "build: Preparing boot files..."
BOOT="$LIVEKITDATA"/"$LIVEKITNAME"/boot
mkdir -p "$BOOT"
mkdir -p "$BOOT"/../changes
mkdir -p "$BOOT"/../bundles
mv "$INITRAMFS" "$BOOT"/initramfs.img
cp bootfiles/* "$BOOT"

# Do substitution
cat bootfiles/syslinux.cfg | sed -r "s:/boot/:/$LIVEKITNAME/boot/:" | \
sed -r "s:MyLinux:$LIVEKITNAME:" > "$BOOT"/syslinux.cfg

echo_livekit_msg "build: BootInstall.*: Replacing 'MyLinux' with '$LIVEKITNAME'..."
cat bootfiles/BootInstall.bat | sed -r "s:/boot/:/$LIVEKITNAME/boot/:" | \
    sed -r "s:\\\\boot\\\\:\\\\$LIVEKITNAME\\\\boot\\\\:" | grep -F -iv "rem" | \
    sed -r "s:MyLinux:$LIVEKITNAME:" > "$BOOT"/BootInstall.bat
cat bootfiles/BootInstall.sh | sed -r "s:MyLinux:$LIVEKITNAME:" > "$BOOT"/BootInstall.sh

echo_livekit_msg "build: Copying kernel..."
cp "$VMLINUZ" "$BOOT"/

# Copy files from include_bund/, but
# do not skip bundle creation
#
if [ -d ./include_bund/ ]; then
    echo_livekit_msg "build: Copying bundles from include_bund/ ..."
    find include_bund/ -type f -name "*.$BEXT" | \
    while read -r  BUND; do
        cp "$BUND" "${LIVEKITDATA}/${LIVEKITNAME}"/bundles/
    done
fi

# create compressed bundles
for i in $MKMOD; do
    echo
    CMDOPT="$(get_exclude "$EXCLUDE" "$i")"
    mkbund "/$i" "${LIVEKITDATA}/${LIVEKITNAME}/00-main-${i}.${BEXT}" \
        $CMDOPT -keep-as-directory
done

# copy rootcopy folder
if [ -d rootcopy/ ]; then
    echo_livekit_msg "build: Copying contents of rootcopy/..."
    cp -a rootcopy/ "$LIVEKITDATA"/"$LIVEKITNAME"/
fi

TARGET=/mnt/z
if [ ! -d "$TARGET" ]; then
    TARGET=/tmp/livekit-build/
fi

if [ ! -d "$TARGET" ]; then
    mkdir -p "$TARGET" &>/dev/null
fi

# Output file
OUT_FILE="${LIVEKITNAME}-${ARCH}-${PID}"

# Checksum file
SUM_FILE="${TARGET}/CHECKSUMS-${OUT_FILE}.TXT"

# Go to Live Kit build data
cd "$LIVEKITDATA" || (sync; exit 1)

# Create ISO image
echo_livekit_msg "build: Creating ISO file for CD boot..."

# How the F@-- can it be more compact than this!?!?
"$MKISOFS" -o "$TARGET/$OUT_FILE.iso" -v -J -R -D -A "$LIVEKITNAME" \
-V "$LIVEKITNAME" -no-emul-boot -boot-info-table -boot-load-size 4 \
-b "$LIVEKITNAME"/boot/isolinux.bin -c \
"$LIVEKITNAME"/boot/isolinux.boot . &>/dev/null
if [ $? -ne 0 ]; then
    echo_warn "build: Failed to generate ISO image!"
    SCAN=
else
    echo_livekit_msg "build: ISO image: $OUT_FILE.iso"
    SCAN=1
fi

# Substitute 'mylinux' with $LIVEKITNAME
cat "$CWD/bootinfo.txt" | grep -F -v "#" | \
    sed -r "s/mylinux/$LIVEKITNAME/" | sed -r "s/\$//" > readme.txt

# Create ZIP archive for "universal" use
echo_livekit_msg "build: Creating ZIP for USB boot..."
rm -f "$TARGET/$OUT_FILE.zip"
zip -1 -r "$TARGET/$OUT_FILE.zip" ./* &>/dev/null
echo_livekit_msg "build: Output file: $OUT_FILE.zip"

echo_livekit_msg "build: Cleaning up..."
cd ..
rm -Rf "$LIVEKITDATA"

# just for aesthetics
echo_livekit_msg "build: Process ID: $PID - Your results is in $TARGET"

# Generate checksum(s)
echo_livekit_msg "build: Generating checksums: Please wait..."

if [ "$SCAN" ]; then
    MD5_ISO="$(md5sum "${TARGET}/${OUT_FILE}".iso 2>/dev/null | cut -d ' ' -f 1)"
else
    MD5_ISO="[ISO image non-existant]"
fi

MD5_ZIP="$(md5sum "${TARGET}/${OUT_FILE}".zip 2>/dev/null | cut -d ' ' -f 1)"

cat >"$SUM_FILE" <<EOF
Linux Live Kit Improved
----------------------------------------
Date: $(date)
Process ID: $PID
Live Kit name: $LIVEKITNAME
MD5 Checksums for this build:
 +  $OUT_FILE.iso - $MD5_ISO
 +  $OUT_FILE.zip - $MD5_ZIP

Have a nice day!
EOF

echo_livekit_msg "build: $OUT_FILE.iso: $MD5_ISO"
echo_livekit_msg "build: $OUT_FILE.zip: $MD5_ZIP"

# Done!
echo_livekit_msg "Build process finished!"
echo "Have a nice day!"


read -pr "Press Enter to continue..." >/dev/null
cd "$CWD" || (sync; exit)
sync
