#!/bin/sh
# Setup booting from disk (USB or harddrive)
# Requires: fdisk, df, tail, tr, cut, dd, sed, awk

# Check if needed tools exists
TOOLS_NEEDED=(fdisk df tail tr cut dd sed awk)
for TOOL in $TOOLS_NEEDED; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        TOOLS_MISSING="$TOOL $TOOLS_MISSING"
    fi
done

if [ -n "$TOOLS_MISSING" ]; then
    echo "$(basename "$0"): You lack some/all of the needed tools:" >&2
    echo "$TOOLS_MISSING" >&2
    exit 1
fi

# Make sure that we are root
if [ $(id -u) -ne 0 ]; then
    echo "> $(basename $0): May not be run by non-root users!" >&2
    exit 1
fi

# change working directory to dir from which we are started
CWD="$(pwd)"
BOOT="$(dirname "$0")"
cd "$BOOT"

# Program definitions
INST_NAME=`basename $0`
INST_PID=$$
LOGFILE="/tmp/$INST_NAME-$INST_PID.log"

# find out device and mountpoint
PART="$(df . | tail -n 1 | tr -s " " | cut -d " " -f 1)"
DEV="$(echo "$PART" | sed -r 's:[0-9]+\$::' | sed -r 's:([0-9])[a-z]+\$:\\1:i')"   #"

# Try to use installed extlinux binary and
# fallback to extlinux.exe only if no installed
# extlinux is not found at all.
echo "Searching for ExtLinux"
EXTLINUX="$(which extlinux 2>/dev/null)"

if [ -z "$EXTLINUX" ]; then
    echo "Falling back to included ExtLinux program..." >&2
    EXTLINUX="./extlinux.exe"
else
    echo "System command: $EXTLINUX"
fi

# Prompt user
#
clear
echo " +-+-+-+-+-+-+-+-+-+-+============+-+-+-+-+-+-+-+-+-+-+-+ "
echo "          Boot setup: MyLinux"
echo " +-+-+-+-+-+-+-+-+-+-+============+-+-+-+-+-+-+-+-+-+-+-+ "
echo "  Current device: $DEV"
echo "  Current partition: $PART"
echo " +-+-+-+-+-+-+-+-+-=+-+-+-+>--<+-+-+-+=-+-+-+-+-+-+-+-+-+ "
echo "  Thank you for choosing MyLinux!"
echo "  Are you sure that you wanna install MyLinux on"
echo "  this device? Make sure that you are not installing on"
echo "  your local drive!"
echo " +-+-+-+-+-+-+-+-+-=+-+-+-+>--<+-+-+-+=-+-+-+-+-+-+-+-+-+ "
echo "  Just press 'Enter' to continue or press Ctrl-C"
echo "  to cancel the installation..."
read -p ' What are you waiting for... ' junk

# Find out the device root resides on
DISK="$(df / | awk '/^\/dev/ {print $1}' | tr -d [0-9])"

# If he/she continues, check which disk are we on
if [ "$DEV" = "$DISK" ]; then
    WARN_DISK=0
else
    WARN_DISK=1
fi

if [ $WARN_DISK -eq 0 ]; then
    # APT-like danger prompt
    CONFIRM_TEXT="Yes, do as I say!"

    echo "> Current partition: $PART" >&2
    echo "> You are about to do something " >&2
    echo "> dangerous to your system!" >&2
    echo "> Type in to continue: 'Yes, do as I say!'"

    read -p " ?] " CONFIRM

    if [ "$CONFIRM" != "$CONFIRM_TEXT" ]; then
       echo "> Incorrect phrase!" >&2
       echo "> No changes were made!" >&2
       exit 1
    fi

fi

echo

# notify user
echo "> WARNING: Do not interrupt at this stage!" >&2
echo "> Installing EXTLinux bootloader: Please wait..." >&2

# install bootloader
"$EXTLINUX" --install "$BOOT" 2>&1 | tee $LOGFILE | cat >&2

if [ $? -ne 0 ]; then
    echo "> Failed to install boot loader!" >&2
    echo "> Please read the errors above (and/or" >&2
    echo "> consult the logfile at /tmp) and press Enter to exit." >&2
    read junk
    exit 1
else
    echo "> Installation of EXTLinux bootloader was successful!"
fi

echo "> Setting up MBR..." >&2

# Setup MBR
if [ "$DEV" != "$PART" ]; then
    # Setup MBR on the first block
    dd bs=440 count=1 conv=notrunc if="$BOOT/mbr.bin" of="$DEV" 2>&1 | tee "$LOGFILE" >/dev/null

    # Toggle the bootable flag
    PART="$(echo "$PART" | sed -r "s:.*[^0-9]::")"
    (
        fdisk -l "$DEV" | fgrep "*" | fgrep "$DEV" | cut -d " " -f 1 \
            | sed -r "s:.*[^0-9]::" | xargs -I '{}' echo -ne "a\n{}\n"
        echo a
        echo $PART
        echo w
    ) | fdisk $DEV 2>&1 | tee "$LOGFILE" >/dev/null
fi

echo "Bootloader installation finished."
cd "$CWD"
