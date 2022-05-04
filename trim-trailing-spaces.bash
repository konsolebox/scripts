#!/bin/bash

# ----------------------------------------------------------------------

# trim-trailing-spaces
#
# Removes trailing spaces in files
#
# Usage: trim-trailing-spaces[.bash] [options] [--] target ...
#
# This tool requires GNU versions of find, grep, sed and stat.
#
# Copyright (c) 2022 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# “Software”), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# ----------------------------------------------------------------------

BACKUP_FILES=false
TRIMMED_COUNT=0
TRIMMING_STARTED=false
VERSION=2022.05.03

function show_summary {
	if [[ TRIMMED_COUNT -gt 1 ]]; then
		echo "${TRIMMED_COUNT} files were trimmed."
	elif [[ TRIMMED_COUNT -eq 1 ]]; then
		echo "A file was trimmed."
	else
		echo "No files were trimmed."
	fi
}

function fail {
	printf '%s\n' "$1" >&2

	if [[ ${TRIMMING_STARTED} == true ]]; then
		echo "Immediately exiting due to failure." >&2
		show_summary >&2
	fi

	exit 1
}

function show_usage {
	echo "Removes trailing spaces in files

Usage: $0 [options] [--] target ...
       $0 -h|--help|-V|--version

Options:
  -b, --backup           Create backup (.bak) files
  -d, --dot-files        Process directories and include files with names
                         beginning with '.' when recursive
  -I, --include pattern  Only include filenames matching pattern when recursive
  -h, --help             Show this usage info and exit
  -r, -R, --recursive    Recursively process files in directories
  -V, --version          Show version and exit
  -X, --exclude pattern  Exclude filenames matching pattern when recursive

Specified targets are not affected by -I or -X, nor require -d to be processed."
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
		fail "No argument specified for '$1'."
	fi

	return 0
}

function trim {
	local file=$1 bak=$1.bak orig_size new_size iopt=-i trim_failed=false
	[[ ${BACKUP_FILES} == true ]] && iopt=-i.bak
	echo "Trimming '${file}'."
	orig_size=$(stat -c '%s' -- "${file}") || fail "Failed to get file size of '${file}'."
	[[ ${BACKUP_FILES} == true && -e ${bak} ]] && fail "Backup file '${bak}' already exists."
	sed "${iopt}" 's@[[:blank:]]\+$@@' -- "${file}" || trim_failed=true
	[[ ${BACKUP_FILES} == true && -e ${bak} ]] && echo "Backup file exists as '${bak}'."
	[[ ${trim_failed} == true ]] && fail "Failed to trim '${file}'."
	new_size=$(stat -c "%s" -- "${file}") || fail "Failed to get new file size of '${file}'."
	[[ new_size -lt orig_size ]] || fail "Failed to trim '${file}'."
	(( ++TRIMMED_COUNT ))
}

function main {
	local file files=() fopts=(-type f) include_dot_files=false recursive=false target targets=()

	while [[ $# -gt 0 ]]; do
		case $1 in
		-b|--backup)
			BACKUP_FILES=true
			;;
		-d|--dot-files)
			include_dot_files=true
			;;
		-h|--help|-\?)
			show_usage
			return 2
			;;
		-I*|--include|--include=*)
			get_opt_and_optarg "${@:1:2}"
			fopts+=(-name "${OPTARG}")
			shift "${OPTSHIFT}"
			;;
		-r|-R|--recursive)
			recursive=true
			;;
		-V|--version)
			echo "${VERSION}"
			return 2
			;;
		-X*|--exclude|--exclude=*)
			get_opt_and_optarg "${@:1:2}"
			fopts+=(-not -name "${OPTARG}")
			shift "${OPTSHIFT}"
			;;
		--)
			targets+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			fail "Invalid option: $1"
			;;
		*)
			targets+=("$1")
			;;
		esac

		shift
	done

	[[ ${#targets[@]} -eq 0 ]] && fail "No target specified."

	if [[ ${include_dot_files} == false ]]; then
		fopts=(-name '.?*' -prune -or "${fopts[@]}")
	elif [[ ${recursive} == false ]]; then
		fail "Include dot files enabled but recursive mode isn't."
	fi

	TRIMMING_STARTED=true

	for target in "${targets[@]}"; do
		if [[ -L ${target} ]]; then
			echo "Refusing to process symbolic link: ${target}"
		elif [[ -f ${target} ]]; then
			grep -qs '[[:blank:]]\+$' -- "${target}" && trim "${target}"
		elif [[ ! -d ${target} ]]; then
			echo "Refusing to process non-regular file: ${target}"
		elif [[ ${recursive} == true ]]; then
			pushd -- "${target}" > /dev/null || \
				fail "Failed to change current directory to '${target}'."

			{
				if [[ BASH_VERSINFO -ge 5 ]]; then
					readarray -d '' -t files
				else
					files=()

					while IFS= read -rd '' file; do
						files+=("${file}")
					done
				fi
			} < <(exec find "${fopts[@]}" -exec grep -lsZ '[[:blank:]]\+$' -- '{}' +)

			for file in "${files[@]}"; do
				trim "${file}"
			done

			popd > /dev/null || fail "Failed to revert current directory."
		else
			echo "Excluding directory target '${target}'."
		fi
	done

	show_summary
	return 0
}

main "$@"
