#!/bin/bash

# ----------------------------------------------------------

# build-and-copy.bash
#
# This script automates building of initrd image using the
# files and directories in the current directory.
#
# It also accepts a '-m' option which makes it copy kernel
# modules to 'lib/modules' before creating the image.
#
# The initrd image is created in the parent directory and
# then copied to /boot.
#
# Usage: [bash] ./build-and-copy.bash [-r|--kernel-release <release>] [-m|--copy-modules]"
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 14, 2021

# ----------------------------------------------------------

if [ -z "${BASH_VERSION}" ]; then
	echo "Bash is need to run this script." >&2
	exit 1
fi

function show_usage_and_exit {
	echo "Usage: $0 [-r|--kernel-release <release>] [-m|--copy-modules]" >&2
	exit 1
}

function fail {
	echo "$1" >&2
	exit 1
}

function get_real_current_dir {
	__=

	if type -P realpath > /dev/null; then
		__=$(realpath "${PWD}") && [[ -n $__ ]] && return 0
	elif type -P readlink > /dev/null; then
		__=$(readlink -f "${PWD}") && [[ -n $__ ]] && return 0
	fi

	return 1
}

shopt -so pipefail || fail "Failed to enable pipefail."

function main {
	local copy_modules=false create_modules_list=false kernel_release= __
	get_real_current_dir || fail "Failed to get real current directory."
	[[ $__ == / ]] && fail 'Refusing to run in /.'

	while [[ $# -gt 0 ]]; do
		case $1 in
		-r|--kernel-release)
			[[ -z $2 ]] && fail "Kernel release not specified."
			kernel_release=$2
			shift
			;;
		-m|--copy-modules)
			copy_modules=true
			;;
		-l|--create-modules-list)
			create_modules_list=true
			;;
		-h|--help)
			show_usage_and_exit
			;;
		*)
			fail "Invalid argument '$1'."
			;;
		esac

		shift
	done

	if [[ -z ${kernel_release} ]]; then
		kernel_release=$(uname -r) && [[ -n ${kernel_release} ]] || \
			fail "Failed to get current kernel release."

		echo "Using current kernel release which is '${kernel_release}'."
	fi

	echo "Deleting 'lib/modules'."
	rm -fr lib/modules
	[[ -e lib/modules ]] && fail "Failed to delete 'lib/modules'."

	if [[ ${copy_modules} == true ]]; then
		echo "Creating 'lib/modules'."
		mkdir lib/modules || fail "Failed to create 'lib/modules'."

		[[ -d /lib/modules/${kernel_release} ]] || \
			fail "Modules directory '/lib/modules/${kernel_release}' does not exist."

		echo "Copying '/lib/modules/${kernel_release}' to 'lib/modules'."

		cp -a "/lib/modules/${kernel_release}" lib/modules/ || \
			fail "Failed to copy '/lib/modules/${kernel_release}' to 'lib/modules'."

		if [[ ${create_modules_list} == true ]]; then
			echo "Creating 'modules_list'."

			find "/lib/modules/${kernel_release}" -name '*.ko' | \
					gawk -F '[/.]' '{ print $(NF - 1) }' | sort -u > modules_list
		fi
	fi

	local build=initramfs-${kernel_release}
	echo "Creating CPIO archive '../${build}'."

	find | sort | cpio -o -H newc | xz --check=none -z -f -9 -c > "../${build}" || \
		fail "Failed to create CPIO archive '../${build}'."

	echo "Copying '../${build}' to '/boot/${build}'."

	cp -a "../${build}" "/boot/${buid}" || \
		fail "Failed to copy '../${build}' to '/boot/${build}'."
}

main "$@"
