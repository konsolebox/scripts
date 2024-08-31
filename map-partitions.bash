#!/bin/bash

# ------------------------------------------------------------------------------

# map-partitions
#
# Maps partitions in a block device to logical devices using dmsetup and sfdisk
#
# Usage: map-partitions[.bash] [options] target [name]
#
# Copyright (c) 2024 konsolebox
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

VERSION=2024.08.31

function die {
	printf '%s\n' "$1" >&2
	exit "${2-1}"
}

function show_warnings {
	echo "WARNING: This tool does not guarantee functionality.
WARNING: Read its code for details on the license regarding its usage."
}

function show_usage_and_exit {
	echo "map-partitions ${VERSION}
Maps partitions in a block device to logical devices using dmsetup and sfdisk
Usage: $0 [options] target [name]

Options:
  -h, --help               Show this help info
  -H, --hide-warnings      Hide warnings
  -n, --dry-run            Enable dry-run mode
  -r, --remove             Remove mappings instead
  -R, --remove-with-force  Same as --remove but don't abort on errors
  -v, --verbose            Enable verbose mode
                           Can be specified twice to increase verbosity.
  -V, --version            Show version
"
	show_warnings
	exit 2
}

function call {
	local dry_run=false q msg= __

	if [[ ${1-} == --dry-run ]]; then
		dry_run=true
		shift
	fi

	for __; do
		printf -v q %q "$__"

		if [[ $q == "$__" ]]; then
			msg+=" $__"
		elif [[ $__ == *\'* ]]; then
			msg+=" $q"
		else
			msg+=" '$__'"
		fi
	done

	printf '%s\n' "> ${msg# }"
	[[ ${dry_run} == true ]] || "$@"
}

function main {
	local target name dev start_key start size_key size id_key id i __
	local args=() dry_run=() hide_warnings=false remove_mode=false remove_mode_forced=false sfdisk \
			verbose=()

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h|--help)
			show_usage_and_exit
			;;
		-H|--hide-warning|--hide-warnings)
			hide_warnings=true
			;;
		-n|--dry-run)
			dry_run=(--dry-run)
			;;
		-r|--remove-mode)
			remove_mode=true
			;;
		-R|--remove-with-force)
			remove_mode=true
			remove_mode_forced=true
			;;
		-v|--verbose)
			verbose+=(-v)
			;;
		-V|--version)
			echo "${VERSION}"
			return 2
			;;
		--)
			args+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			die "Invalid option: $1"
			exit 1
			;;
		*)
			args+=("$1")
			;;
		esac

		shift
	done

	set -- "${args[@]}"
	[[ $# -eq 1 || $# -eq 2 ]] || show_usage_and_exit
	sfdisk=$(type -P sfdisk) || die "sfdisk command not found."

	if [[ ${hide_warnings} == false ]]; then
		show_warnings >&2
		echo >&2
	fi

	if [[ ${dry_run+.} ]]; then
		echo "Dry run is enabled."
		echo
	fi

	target=$1 name=${2-${1##*/}} i=1

	while IFS=' :,=' read -ru 4 dev start_key start size_key size id_key id; do
		if [[ ${start_key} == start && size -gt 0 ]]; then
			if [[ ${remove_mode} == true ]]; then
				call "${dry_run[@]}" dmsetup "${verbose[@]}" remove "${name}p${i}" || \
					[[ ${remove_mode_forced} == true ]] || \
						return
			else
				call "${dry_run[@]}" dmsetup "${verbose[@]}" create "${name}p${i}" \
						--table "0 ${size} linear ${target} ${start}" || \
					[[ ${remove_mode_forced} == true ]] || \
						return
			fi

			(( ++i ))
		fi
	done 4< <(exec "${sfdisk}" -df "${target}")
}

main "$@"
