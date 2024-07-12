#!/bin/bash

# ------------------------------------------------------------------------------
#
# git-amend-date-using-reference
#
# Updates current commit's date using another commit's date as reference.
#
# Usage: git-amend-date-using-reference[.bash] reference [options]
#
# This tool requires git.
#
# Copyright (c) 2024 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ------------------------------------------------------------------------------

_DRY_RUN=false
_VERBOSE=false
_VERSION=2024.07.12

function err {
	printf '%s\n' "${1-}" 2>&1
	return "${2-1}"
}

function die {
	err "$@"
	exit
}

function call {
	local allow_dry_run=false

	if [[ ${1-} == --allow-dry-run ]]; then
		allow_dry_run=true
		shift
	fi

	if [[ ${_VERBOSE} == true ]]; then
		local q msg= __

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

		printf '%s\n' "> ${msg# }" >&2
	fi

	[[ ${allow_dry_run} == true && ${_DRY_RUN} == true ]] || command "$@"
}

function show_usage_and_exit {
	local basename=${0##*/}

	echo "Usage: ${basename} reference [-n|--dry-run] [-v|--verbose]
       ${basename//?/ } -h|--help|-V|--version

Options:
  -h, --help     Show this usage info and exit
  -n, --dry-run  Don't make actual changes
  -v, --verbose  Be verbose
  -V, --version  Show version and exit"

	exit 2
}

function main {
	local date reference=()

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h|--help)
			show_usage_and_exit
			;;
		-n|--dry-run)
			_DRY_RUN=true
			;;
		-v|--verbose)
			_VERBOSE=true
			;;
		-V|--version)
			echo "${_VERSION}"
			return 2
			;;
		--)
			reference+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			die "Invalid option: $1"
			;;
		*)
			reference+=("$1")
			;;
		esac

		shift
	done

	if [[ -z ${reference+.} ]]; then
		err "Please specify a reference."
		err
		show_usage_and_exit
	elif [[ ${#reference[@]} -gt 1 ]]; then
		die "Too many references specified."
	fi

	date=$(call git show -s --format=%ci "${reference}") && [[ ${date} ]] || \
		die "Failed to get date using '${reference}' as reference."

	call --allow-dry-run git commit --amend --date="${date}" || \
		die "An error occurred while trying to update commit's date."
}

main "$@"
