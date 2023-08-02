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
# Usage: [bash] ./build-and-copy.bash [options]
#
# Author: konsolebox
# Copyright Free / Public Domain
# Aug. 2, 2023

# ----------------------------------------------------------

if [ -z "${BASH_VERSION}" ]; then
	echo "Bash is need to run this script." >&2
	exit 1
fi

function show_usage_and_exit {
	echo "Creates an initrd image using files in current directory, saves it to parent
directory, and copies it to /boot

Usage: $0 [options]

Important Options:
  -r, --kernel-release RELEASE  Specify kernel's release name.  If this is
                                omitted, the output of 'uname -r' is used.
  -m, --copy-modules            Copy /lib/modules/RELEASE to lib/modules before
                                creating the image

Other Options:
  -l, --create-modules-list     Create a 'modules_list' file which will contain
                                a list of modules in 'lib/modules'
  -n|--no-backup                Do not create a backup of initrd file in /boot
                                before overriding it
  -h, --help                    Show this usage info and exit

The 'lib/modules' directory and the 'modules_list' file always get deleted
before any operation."
	exit 2
}

function fail {
	printf '%s\n' "$1" >&2
	exit "${2-1}"
}

function get_opt_and_optarg {
	OPT=$1 OPTARG= OPTSHIFT=0

	if [[ $1 == -[!-]?* ]]; then
		OPT=${1:0:2} OPTARG=${1:2}
	elif [[ $1 == --*=* ]]; then
		OPT=${1%%=*} OPTARG=${1#*=}
	elif [[ ${2+.} ]]; then
		OPTARG=$2 OPTSHIFT=1
	else
		return 1
	fi

	return 0
}

shopt -so pipefail || fail "Failed to enable pipefail."

function main {
	local copy_modules=false create_modules_list=false do_backup=true \
			kernel_release= real_current_dir __

	real_current_dir=$(pwd -P) || fail "Failed to get real current directory."
	[[ ${real_current_dir} == / ]] && fail "Refusing to run in /."

	while [[ $# -gt 0 ]]; do
		case $1 in
		-r*|--kernel-release|--kernel-release=*)
			get_opt_and_optarg "${@:1:2}" || fail "Kernel release not specified."
			kernel_release=${OPTARG}
			shift "${OPTSHIFT}"
			;;
		-n|--no-backup)
			do_backup=false
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
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		*)
			fail "Invalid argument: $1" 2
			;;
		esac

		shift
	done

	[[ ${create_modules_list} == true && ${copy_modules} == false ]] && \
		fail "Create-modules-list option requires copy-modules option."

	if [[ -z ${kernel_release} ]]; then
		kernel_release=$(uname -r) && [[ -n ${kernel_release} ]] || \
			fail "Failed to get current kernel release."

		echo "Using current kernel release which is '${kernel_release}'."
	fi

	for __ in lib/modules modules_list; do
		if [[ -e $__ ]]; then
			echo "Deleting '$__'."
			rm -fr -- "$__" && [[ ! -e $__ ]] || fail "Failed to delete '$__'."
		fi
	done

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
					gawk -F '[/.]' '{ print $(NF - 1) }' | sort -u > modules_list || \
				fail "Failed to create 'modules_list'."
		fi
	fi

	local build=initramfs-${kernel_release}
	echo "Creating CPIO archive '../${build}'."

	find . -not -path '*/.git*' | sort | cpio -o -H newc | \
			xz --check=none -z -f -9 -c > "../${build}" || \
		fail "Failed to create CPIO archive '../${build}'."

	if [[ ${do_backup} == true && -e /boot/${build} ]]; then
		echo "Backing up '/boot/${build}' as '/boot/${build}.bak'."
		cp -a "/boot/${build}"{,.bak} || \
			fail "Failed to create '/boot/${build}.bak'."
	fi

	echo "Copying '../${build}' to '/boot/${build}'."
	cp -a "../${build}" "/boot/${buid}" || \
		fail "Failed to copy '../${build}' to '/boot/${build}'."
}

main "$@"
