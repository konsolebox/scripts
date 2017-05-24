#!/bin/bash

# ----------------------------------------------------------

# rcopy
#
# Copies files along with their dependencies to a virtual
# root directory.  The resulting file's path is reproduced
# based on its source.
#
# Usage: [bash] rcopy[.sh] [options] -t directory source ...
#        [bash] rcopy[.sh] [options] source ... directory
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 24, 2017

# ----------------------------------------------------------

# TODO: Support symbolic-link path nodes containing absolute paths,
#       by converting them to relative forms.

[[ ${BASH_VERSINFO} -ge 4 ]] || {
	echo "Bash version 4.0 or newer is needed to run this script." >&2
	exit 1
}

CP_OPTS=()
HARD_LINK_MODE=false
TARGET_ROOT=
VERBOSE=false
QUIET=false
VERSION=2017-05-24

declare -A PROCESSED=()

function log_message {
	[[ ${QUIET} == false ]] && echo "rcopy: $1"
}

function log_warning {
	echo "rcopy: Warning: $1"
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
  -V, --version    Show version.

Disclaimer: This tool comes with no warranty."
}

function get_clean_path {
	local T1 T2=() I=0 IFS=/

	if [[ $1 == /* ]]; then
		read -ra T1 <<< "$1"
	else
		read -ra T1 <<< "${PWD}/$1"
	fi

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -gt 0 ]] || fail "Path tries to get the parent directory of '/': $1"
			unset 'T2[--I]'
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

function cp {
	local MESSAGES R
	MESSAGES=$(command cp "${CP_OPTS[@]}" "$@" 2>&1)
	R=$?

	if [[ -n ${MESSAGES} ]]; then
		local LINES=()
		readarray -t LINES <<< "${MESSAGES}"
		printf 'rcopy: cp: %s\n' "${LINES[@]}"
	fi

	return "$R"
}

function copy_dir_structure {
	local SOURCE_TREE=() DEST_DIR=$2 CURRENT_SOURCE= LINK_TARGET __
	IFS=/ read -ra SOURCE_TREE <<< "$1"

	for __ in "${SOURCE_TREE[@]}"; do
		[[ -z $__ ]] && continue
		CURRENT_SOURCE+=/$__

		if [[ -L ${CURRENT_SOURCE} ]]; then
			[[ ! -d ${CURRENT_SOURCE} ]] && fail "Parent path node of a source tree is expected to be a directory but isn't: ${CURRENT_SOURCE}"

			LINK_TARGET=$(readlink "${CURRENT_SOURCE}") && [[ -n ${LINK_TARGET} ]] || fail "Unable to get link's target: ${CURRENT_SOURCE}"
			[[ ${LINK_TARGET} == /* ]] && fail "Symbolic-link path nodes that resolve to absolute paths are not yet supported: \"${CURRENT_SOURCE}\" -> \"${LINK_TARGET}\""

			if [[ -e ${DEST_DIR}${CURRENT_SOURCE} ]]; then
				if [[ -L ${DEST_DIR}${CURRENT_SOURCE} ]]; then
					log_warning "Overwriting existing link \"${DEST_DIR}${CURRENT_SOURCE}\" with \"${CURRENT_SOURCE}\"."
				else
					fail "Unable to copy symbolic link from \"${CURRENT_SOURCE}\" to \"${DEST_DIR}${CURRENT_SOURCE}\" since a file or directory already exists."
				fi
			fi

			log_message "Copying symbolic link \"${CURRENT_SOURCE}\" (-> \"${LINK_TARGET}\") to \"${DEST_DIR}${CURRENT_SOURCE}\""
			log_verbose "Command: cp ${CP_OPTS[*]} -d -- \"${CURRENT_SOURCE}\" \"${DEST_DIR}${CURRENT_SOURCE}\""
			cp "${CP_OPTS[@]}" -d -- "${CURRENT_SOURCE}" "${DEST_DIR}${CURRENT_SOURCE}" || fail "Copy failed."

			get_clean_path "${CURRENT_SOURCE}/../${LINK_TARGET}"
			copy_dir_structure "$__" "${DEST_DIR}"
		elif [[ -d ${CURRENT_SOURCE} ]]; then
			if [[ ! -e ${DEST_DIR}${CURRENT_SOURCE} ]]; then
				log_message "Creating directory \"${DEST_DIR}${CURRENT_SOURCE}\"."
				mkdir -- "${DEST_DIR}${CURRENT_SOURCE}" || fail "Unable to create directory \"${DEST_DIR}${CURRENT_SOURCE}\"."
			elif [[ ! -d ${DEST_DIR}${CURRENT_SOURCE} ]]; then
				fail "\"${DEST_DIR}${CURRENT_SOURCE}\" already exists but is not a directory."
			fi
		else
			fail "Parent path node of a source tree is neither a directory nor a symbolic link: ${CURRENT_SOURCE}"
		fi
	done
}

function process {
	local DEPS DEST DEST_DIR __

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
			copy_dir_structure "${__%/*}" "${TARGET_ROOT}"
		elif [[ ! -d ${DEST_DIR} ]]; then
			fail "Destination directory \"${DEST_DIR}\" already exists but is not a directory."
		fi

		if [[ -z ${PROCESSED[$__]} ]]; then
			if [[ ${HARD_LINK_MODE} == true ]]; then
				log_message "Hard-linking \"$__\" to \"${DEST_DIR}/\"."
				cp -a -H -- "$__" "${DEST_DIR}/"
			else
				log_message "Copying \"$__\" to \"${DEST_DIR}/\"."
				cp -a -- "$__" "${DEST_DIR}/"
			fi

			[[ $? -eq 0 ]] || fail "Copy failed."
			PROCESSED[$__]=.
		fi
	done
}

function main {
	local FILE_ARGS=()

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

	[[ ${TARGET_ROOT} == / ]] && fail "Target root directory can't be '/'."

	process "${FILE_ARGS[@]}"
}

main "$@"
