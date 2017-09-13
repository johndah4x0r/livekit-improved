#!/bin/bash

# CPIO+XZ utility
# Author: 'JohnDaH4x0r' <terencedoesmc12 AT gmail.com>

# Data & variables
PROG="$(basename $0)"
PID=$$
RANDOM="$(echo $(($RANDOM * $PID)) | base64)"
CWD="$(pwd)"

# Functions

# Make random output
# P.S: Not as secure as /dev/urandom or 'mktemp'
# $1: Random seed
#
mkrand() {
    local SEED RAND_CHUNK RANDNAME

    SEED=$1

    if [ "${SEED}" = "" ]; then
        SEED=$RANDOM
    fi

    RANDOM=$SEED
    RAND_CHUNK="${RANDOM}"
    RAND_CHUNK="$(dd if=/dev/urandom bs=1 count=8)+${RAND_CHUNK}"
    RANDNAME="$(echo $RAND_CHUNK | base64)"
    echo "$RANDNAME" | tr -d "=" | tr -d "/"
}

# Create CPIO+XZ archive
# $1: Source directory
# $2: Archive name
#
mkcpxz() {
    local SRCDIR ARNAME
    SRCDIR="$1"
    ARNAME="$2"

    if [ ! -e "${SRCDIR}" ]; then
        error "${SRCDIR}: No such file or directory!"
    fi

    if [ "${ARNAME}" = "" ]; then
        ARNAME="$(basename ${SRCDIR}).${PID}.cpio.xz"
    fi

    (cd "$SRCDIR" && find . | cpio -o -H newc | \
        xz --extreme > "${CWD}/$ARNAME" 2>/dev/null)

    if [ $? -ne 0 ]; then
        error "${SRCDIR}: Failed to create archive!"
    fi

}

uncpxz() {
    local SRC_AR DESTDIR
    SRC_AR="$(realpath $1 2>/dev/null)"
    DESTDIR="$(realpath $2 2>/dev/null)"

    if [ ! -e "${SRC_AR}" ]; then
        error "${SRC_AR}: No such file or directory!"
    elif [ ! -f "${SRC_AR}" ]; then
        error "${SRC_AR}: No such file exists!"
    fi

    if [ ! -d "${DESTDIR}" ]; then
        mkdir "${DESTDIR}" 2>/dev/null
    elif [ "${DESTDIR}" = "" ]; then
        DESTDIR="$(basename ${SRC_AR})-cpxz_root"
        mkdir "${DESTDIR}" 2>/dev/null
    fi

    ( cd "$DESTDIR" && \
        dd if="${SRC_AR}" 2>/dev/null | unxz - | cpio -id -p .)

    if [ $? -ne 0 ]; then
        error "${SRC_AR}: Failed to extract archive!"
    fi
}

error() {
    ERRMSG="$*"
    echo "${PROG}: ErrMsg: ${ERRMSG}" >&2
    exit 1
}

usage() {
    # Print out usage
    cat >&2 <<END
${PROG} - Usage:
    ${PROG} [-h | --help]
    ${PROG} [-c | --create]  <srcdir>  [-t | --target] <target>
    ${PROG} [-x | --extract] <src_ar>  [-t | --target] <target>

Dependencies:
  * cpio
  * xz & unxz (xz-utils)
END

    if [ "$1" != "" ]; then
        error "$1"
        exit 1
    fi

}

parse_args() {
    local KEY SRCDIR SRC_AR TARGET
    while [[ $# -gt 1 ]]; do
        KEY="$1"
        case "$KEY" in
            "-c" | "--create")
                SRCDIR="$2"
                MODE=128
                shift
                
                ;;
            "-x" | "--extract")
                SRC_AR="$2"
                MODE=256
                shift
                ;;
            "-t" | "--target")
                TARGET="$2"
                shift
                ;;
            *)
                usage "Failed to interprete argument: ${KEY}"
                ;;
        esac
        shift
    done

    # Return output (soon interpreted)
    case "${MODE}" in
        128)
            echo "${MODE}#${SRCDIR}#${TARGET}"
            return
            ;;
        256)
            echo "${MODE}#${SRC_AR}#${TARGET}"
            return
            ;;
    esac
}


if (echo "$*" | grep -q "\-h") || (echo "$*" | grep -q "\--help"); then
    usage
    exit 0
elif [ $# -lt 2 ]; then
    usage "Expected at least 2 arguments; Got $#"
fi


OUTPUT="$(parse_args $*)"
MODE="$(echo "$OUTPUT" | cut -d '#' -f 1)"
SOURCE="$(echo "$OUTPUT" | cut -d '#' -f 2)"
TARGET="$(echo "$OUTPUT" | cut -d '#' -f 3)"

# Final check
CPIO="$(which cpio 2>/dev/null)"
XZ="$(which xz 2>/dev/null)"
UNXZ="$(which unxz 2>/dev/null)"

if [ "$CPIO" = "" ] || [ "$XZ" = "" ] || [ "$UNXZ" = "" ]; then
    usage "Components missing: cpio || xz || unxz"
fi

case "$MODE" in
    128)
        mkcpxz "${SOURCE}" "${TARGET}"
        ;;
    256)
        uncpxz "${SOURCE}" "${TARGET}"
        ;;
esac




    




