#!/bin/bash

# ----------------------------------------------------------

# init/build-and-copy
#
# This is a script I ended up with to automate building of
# Initrd.
#
# Usage: build-and-copy.sh [-r|--kernel-release <release>] [-m|--copy-modules]"
#
# Author: konsolebox
# Copyright Free / Public Domain
# August 24, 2014

# ----------------------------------------------------------

COPY_MODULES=false
KERNEL_RELEASE=$(uname -r)

function show_usage_info {
	echo "Usage: $0 [-r|--kernel-release <release>] [-m|--copy-modules]"
	exit 1
}

while [[ $# -gt 0 ]]; do
	case $1 in
	-m|--copy-modules)
		COPY_MODULES=true
		;;
	-r|--kernel-release)
		if [[ -z $2 ]]; then
			echo "Kernel release not specified." >&2
			exit 1
		fi
		KERNEL_RELEASE=$2
		shift
		;;
	-h|--help)
		show_usage_info
		exit 1
		;;
	*)
		echo "Invalid argument \"$1\"."
		exit 1
		;;
	esac
	shift
done

rm -fr lib/modules

if [[ -e lib/modules ]]; then
	echo "Failed to remove \"lib/modules\"."
	exit 1
fi

if [[ $COPY_MODULES == true ]]; then
	echo "Creating \"lib/modules\"."

	mkdir lib/modules || {
		echo "Failed to create \"lib/modules\"." >&2
		exit 1
	}

	if [[ ! -d /lib/modules/$KERNEL_RELEASE ]]; then
		echo "Modules directory \"/lib/modules/$KERNEL_RELEASE\" does not exist." >&2
		exit 1
	fi

	echo "Copying \"/lib/modules/$KERNEL_RELEASE\" to \"lib/modules\"."

	cp -a "/lib/modules/$KERNEL_RELEASE" lib/modules/ || {
		echo "Failed to copy modules \"/lib/modules/$KERNEL_RELEASE\" to \"lib/modules\"." >&2
		exit 1
	}
fi

BUILD="initramfs-$KERNEL_RELEASE"

shopt -s -o pipefail

echo "Creating CPIO archive ../$BUILD."

find | sort | cpio -o -H newc | xz --check=none -z -f -9 -c > "../$BUILD" || {
	echo "Failed to create CPIO archive \"../$BUILD\"." >&2
	exit 1
}

echo "Copying \"../$BUILD\" to \"/boot/$BUILD\"."

cp -a "../$BUILD" "/boot/$BUILD" || {
	echo "Failed to copy \"../$BUILD\" to \"/boot/$BUILD\"." >&2
	exit 1
}
