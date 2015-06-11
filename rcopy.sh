#!/bin/bash

# ----------------------------------------------------------

# rcopy
#
# Copies files along with their dependencies to a virtual
# root directory.  The resulting file's path is reproduced
# based on its source.
#
# Usage: rcopy[.sh] [options] -t directory source ...
#        rcopy[.sh] [options] source ... directory
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 11, 2015

# ----------------------------------------------------------

# TODO: Directories of targets need to be cloned properly as well.
#       They could be a link or not.

[[ ${BASH_VERSINFO} -ge 4 ]] || {
	echo "Bash version 4.0 or newer is needed to run this script." >&2
	exit 1
}

CP_OPTS=()
FILE_ARGS=()
HARD_LINK_MODE=false
TARGET_ROOT=''
VERBOSE=false
QUIET=false
VERSION=2015-06-11

declare -A PROCESSED=()

function log_message {
	[[ ${QUIET} == false ]] && echo "rcopy: $1"
}

function log_verbose {
	[[ ${VERBOSE} == true ]] && echo "rcopy: $1"
}

function log_error {
	echo "rcopy: Error: $1"
}

function fail {
	log_error "$1"
	exit 1
}

function show_help_info {
	echo "Copies files along with their dependencies to a virtual root directory.
The resulting file's path is reproduced based from its source.

Usage: $0 [options] -t directory source ...
       $0 [options] source ... directory

  -h, --help       Show this help info.
  -H, --hard-link  Hard-link files instead of copying.
  -q, --quiet      Show no message.
  -v, --verbose    Be verbose.
  -V, --version    Show version."
}

function get_clean_path {
	local T1 T2=() I=0 IFS=/

	if [[ $1 == /* ]]; then
		read -ra T1 <<< "$1"
	else
		read -ra T1 <<< "$PWD/$1"
	fi

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -gt 0 ]] && unset 'T2[--I]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		T2[I++]=$__
	done

	__="/${T2[*]}"
}

function process {
	local DEPS DEST DEST_DIR L LINES MESSAGES RESULT __

	for __; do
		if [[ -L $__ ]]; then
			process "$(readlink -m -- "$__")"
		elif [[ -f $__ && -x $__ ]]; then
			DEPS=()
			readarray -t DEPS < <(exec ldd "$__" | grep -Po '/\S+')
			process "${DEPS[@]}"
		fi

		DEST=${TARGET_ROOT}$__
		DEST_DIR=${DEST%/*}

		if [[ ! -e ${DEST_DIR} ]]; then
			mkdir -p -- "${DEST_DIR}"
		elif [[ ! -d ${DEST_DIR} || -L ${DEST_DIR} ]]; then
			fail "Destination directory ${DEST_DIR} already exists but is not a directory."
		fi

		if [[ -z ${PROCESSED[$__]} ]]; then
			if [[ ${HARD_LINK_MODE} == true ]]; then
				log_message "Hard-linking \"$__\" to \"${DEST_DIR}\"."
				log_verbose "Command: cp ${CP_OPTS[*]} -a -H -- \"$__\" \"${DEST_DIR}\""
				MESSAGES=$(cp "${CP_OPTS[@]}" -a -H -- "$__" "${DEST_DIR}" 2>&1)
			else
				log_message "Copying \"$__\" to \"${DEST_DIR}\"."
				log_verbose "Command: cp ${CP_OPTS[*]} -a -- \"$__\" \"${DEST_DIR}\""
				MESSAGES=$(cp "${CP_OPTS[@]}" -a -- "$__" "${DEST_DIR}" 2>&1)
			fi

			RESULT=$?

			if [[ -n ${MESSAGES} ]]; then
				LINES=()
				readarray -t LINES <<< "${MESSAGES}"
				printf 'cp: %s\n' "${LINES[@]}"
			fi

			[[ ${RESULT} -ne 0 ]] && fail "Copy failed."

			log_verbose
			PROCESSED[$__]=.
		fi
	done
}

while [[ $# -gt 0 ]]; do
	case $1 in
	-h|--help)
		show_help_info
		exit 1
		;;
	-H|--hard-link)
		HARD_LINK_MODE=true
		;;
	-q|--quiet)
		QUIET=true
		VERBOSE=false
		;;
	-t|--target-root)
		TARGET_ROOT=$2
		shift
		;;
	-v|--verbose)
		QUIET=false
		VERBOSE=true
		CP_OPTS=("-v")
		;;
	-V|--version)
		echo "${VERSION}"
		exit 1
		;;
	--)
		shift

		for __; do
			[[ ! -e $__ ]] && fail "File or directory does not exist: $__"

			get_clean_path "$__"
			FILE_ARGS+=("$__")
		done

		break
		;;
	-*)
		fail "Invalid option: $1"
		;;
	*)
		[[ ! -e $1 ]] && fail "File or directory does not exist: $1"

		get_clean_path "$1"
		FILE_ARGS+=("$__")
		;;
	esac

	shift
done

[[ ${#FILE_ARGS[@]} -eq 0 ]] && fail "No source file specified."

if [[ -z ${TARGET_ROOT} ]]; then
	[[ ${#FILE_ARGS[@]} -lt 2 ]] && fail "No target directory specified."

	TARGET_ROOT=${FILE_ARGS[@]:(-1)}
	unset "FILE_ARGS[${#FILE_ARGS[@]} - 1]"
fi

[[ ${TARGET_ROOT} == / ]] && fail "Target root directory can't be /."

process "${FILE_ARGS[@]}"
