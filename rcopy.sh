#!/bin/bash

# ----------------------------------------------------------

# rcopy
#
# Copies files along with their dependencies to a virtual
# root directory.  The resulting file's path is reproduced
# based from its source.
#
# Usage: rcopy[.sh] [options] -t directory source ...
#        rcopy[.sh] [options] source ... directory
#
# Author: konsolebox
# Copyright Free / Public Domain
# August 25, 2014

# ----------------------------------------------------------

# TODO: Directories of targets need to be cloned properly as well.
#       They could be a link or not.

declare    TARGET_ROOT=''
declare -a FILE_ARGS=()
declare -a CP_OPTS=()
declare -A PROCESSED=()
declare    VERBOSE=false
declare    VERSION=2014-08-21

function log_message {
	echo "$1"
}

function log_verbose {
	[[ $VERBOSE == true ]] && echo "$1"
}

function log_error {
	echo "$1" >&2
}

function show_help_info {
	{
		echo "Copies files along with their dependencies to a virtual root directory."
		echo "The resulting file's path is reproduced based from its source."
		echo
		echo "Usage: $0 [options] -t directory source ..."
		echo "       $0 [options] source ... directory"
		echo
		echo "  -h, --help       Show this help info."
		echo "  -v, --verbose    Be verbose."
		echo "  -V, --version    Show version."
	} >&2
}

function get_clean_path {
	local -a T1 T2=()
	local -i I=0
	local IFS=/ A

	if [[ $1 == /* ]]; then
		read -a T1 <<< "$1"
	else
		read -a T1 <<< "$PWD/$1"
	fi

	for A in "${T1[@]}"; do
		case "$A" in
		..)
			[[ I -gt 0 ]] && unset 'T2[--I]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		T2[I++]=$A
	done

	__="/${T2[*]}"
}

function process {
	local __ MESSAGES RESULT LINES L
	for __; do
		if [[ -L $__ ]]; then
			process "$(readlink -m -- "$__")"
		elif [[ -f $__ && -x $__ ]]; then
			local DEPS
			readarray -t DEPS < <(exec ldd "$__" | grep -Po '/\S+')
			process "${DEPS[@]}"
		fi
		local DEST=${TARGET_ROOT}$__
		local DEST_DIR=${DEST%/*}
		if [[ ! -e $DEST_DIR ]]; then
			mkdir -p -- "$DEST_DIR"
		elif [[ ! -d $DEST_DIR || -L $DEST_DIR ]]; then
			log_error "Target directory $DEST_DIR already exists but is not a directory."
			exit 1
		fi
		if [[ -z ${PROCESSED[$__]} ]]; then
			log_message "Copying \"$__\" to \"$DEST_DIR\"."
			MESSAGES=$(cp "${CP_OPTS[@]}" -a -- "$__" "$DEST_DIR" 2>&1)
			RESULT=$?
			if [[ -n $MESSAGES ]]; then
				readarray -t LINES <<< "$MESSAGES"
				printf 'cp: %s\n' "${LINES[@]}"
			fi
			if [[ $RESULT -ne 0 ]]; then
				log_error "Failed."
				exit 1
			fi
			log_verbose
			PROCESSED[$__]=.
		fi
	done
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h|--help)
		show_help_info
		exit 1
		;;
	-t|--target-root)
		TARGET_ROOT=$2
		shift
		;;
	-v|--verbose)
		VERBOSE=true
		CP_OPTS=("-v")
		;;
	-V|--version)
		log_message "$VERSION"
		exit 1
		;;
	--)
		shift
		for __; do
			if [[ ! -e $__ ]]; then
				log_error "File or directory does not exist: $__"
				exit 1
			fi
			get_clean_path "$__"
			FILE_ARGS+=("$__")
		done
		break
		;;
	-*)
		log_error "Invalid option: $1"
		exit 1
		;;
	*)
		if [[ ! -e $1 ]]; then
			log_error "File or directory does not exist: $1"
			exit 1
		fi
		get_clean_path "$1"
		FILE_ARGS+=("$__")
		;;
	esac
	shift
done

if [[ ${#FILE_ARGS[@]} -eq 0 ]]; then
	log_error "No source file specified."
	exit 1
fi

if [[ -z $TARGET_ROOT ]]; then
	if [[ ${#FILE_ARGS[@]} -lt 2 ]]; then
		log_error "No target directory specified."
		exit 1
	fi

	TARGET_ROOT=${FILE_ARGS[@]:(-1)}
	unset "FILE_ARGS[${#FILE_ARGS[@]} - 1]"
fi

if [[ $TARGET_ROOT == / ]]; then
	log_error "Target root directory can't be /."
	exit 1
fi

process "${FILE_ARGS[@]}"
