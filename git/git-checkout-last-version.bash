#!/bin/bash

# ------------------------------------------------------------------------------

# git-checkout-last-version
#
# Extracts the last version of a file before it was removed from git
#
# Usage: git-checkout-laster-version[.bash] [options] [--] file
#
# This script may or may not support directories.  It requires git.
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

# ------------------------------------------------------------------------------

[ -n "${BASH_VERSION}" ] && [[ BASH_VERSINFO -ge 4 ]] || {
	echo "Bash version 4.0 or newer is required to run this script."
	exit 1
}

shopt -s extglob || exit 1

_VERBOSE=false
_VERSION=2024.08.25

function call {
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

	"$@"
}

function die {
	printf '%s\n' "$1" 2>&1
	exit "${2-1}"
}

function show_usage {
	echo "Extracts the last version of a file before it was removed from git

This script may or may not support directories.

Usage: $0 [-v|--verbose ] [--] file
       $0 -h|--help|-V|--version

Options:
  -h, --help     Show this usage info and exit
  -v, --verbose  Show git commands being executed
  -V, --version  Show version and exit"
}

function main {
	local commit file=() output IFS=$' \t\n'

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h|--help|-\?)
			show_usage
			return 2
			;;
		-v|--verbose)
			_VERBOSE=true
			;;
		-V|--version)
			echo "${_VERSION}"
			return 2
			;;
		--)
			file+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			die "Invalid option: $1" 2
			;;
		*)
			file+=("$1")
			;;
		esac

		shift
	done

	[[ ${#file[@]} -eq 0 ]] && die "No file specified."
	[[ ${#file[@]} -gt 1 ]] && die "Only one file can be specified."
	[[ ${file} == @(|.|..) ]] && die "Invalid file argument: ${file}"

	output=$(call git log --name-status --pretty=oneline --diff-filter=d --max-count=1 -- "${file}") || \
		die "Failed to find commit for '${file}'."
	[[ ${output} ]] || die "No commit found for '${file}'."
	commit=${output%%[[:blank:]]*}
	[[ ${commit} =~ ^[[:alnum:]]{40}$ ]] || die "Invalid commit ID extracted: ${commit}"
	call git checkout "${commit}" -- "${file}" || die "Failed to checkout '${file}' in ${commit}."
}

main "$@"
