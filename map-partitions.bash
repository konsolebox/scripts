#!/bin/bash

# ------------------------------------------------------------------------------

# map-partitions
#
# Maps partitions in a block device to logical devices using dmsetup and sfdisk
#
# Usage: map-partitions[.bash] [options] target [name]
#
# Copyright (c) 2021 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ------------------------------------------------------------------------------

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires bash." >&2
	exit 1
}

shopt -s extglob || exit 1

VERSION=2021.05.14

function show_warnings {
	echo "WARNING: This tool does not guarantee functionality.
WARNING: It has only been tested with MSDOS partitions.
WARNING: Read its code for details on the license regarding its usage."
}

function show_usage_and_exit {
	echo "map-partitions ${VERSION}
Maps partitions in a block device to logical devices using dmsetup and sfdisk
Usage: $0 [options] target [name]

Options:
  -h, --help           Show this help info.
  -H, --hide-warnings  Hide warnings.
  -V, --version        Show version.
"
	show_warnings
	exit 1
}

function call {
	local msg=() i=0 __

	for __; do
		[[ $__ != +([[:alnum:]_\-=+,.:@]) ]] && __=\"${__//\"/\\\"}\"
		msg[i++]=$__
	done

	printf '%s\n' "${msg[@]}"
	"$@"
}

function main {
	local target name dev start_key start size_key size id_key id i __
	local args=() hide_warnings=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h|--help)
			show_usage_and_exit
			;;
		-H|--hide-warning|--hide-warnings)
			hide_warnings=true
			;;
		-V|--version)
			echo "${VERSION}"
			exit 1
			;;
		*)
			args+=("$1")
			;;
		--)
			args+=("${@:2}")
			break
			;;
		-*)
			echo "Invalid option: $1" >&2
			exit 1
			;;
		esac

		shift
	done

	set -- "${args[@]}"
	[[ $# -eq 1 || $# -eq 2 ]] || show_usage_and_exit
	[[ ${hide_warnings} == true ]] || show_warnings >&2
	target=$1 name=${2-${1##*/}} i=1

	while IFS=' :,=' read -ru 4 dev start_key start size_key size id_key id; do
		if [[ ${start_key} == start && size -gt 0 ]]; then
			call dmsetup create "${name}p${i}" --table "0 ${size} linear ${target} ${start}" || \
				return 1
			(( ++i ))
		fi
	done 4< <(exec sfdisk -df "${target}")
}

main "$@"
