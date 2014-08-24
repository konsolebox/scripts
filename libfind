#!/bin/bash

# ----------------------------------------------------------

# libfind
#
# Searches for library files in /lib, /usr/lib,
# /usr/local/lib and other paths found in /etc/ld.so.conf.
#
# Usage: libfind[.sh] <partstring> [partstring2, ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# August 24, 2014

# ----------------------------------------------------------

# Check Bash version.

[[ $BASH_VERSINFO -ge 3 ]] || {
	echo "This script requires Bash version 3.0 or newer."
	return 1
}

# Default paths to search from.

LIBPATHS=(/lib /usr/lib /usr/local/lib)

# Enable extended patterns.

shopt -s extglob

# Functions

function getabspath {
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
			[[ I -gt 0 ]] && unset T2\[--I\]
			continue
			;;
		.|'')
			continue
			;;
		esac

		T2[I++]=$A
	done

	if [[ $1 == */ ]]; then
		if [[ I -ne 0 ]]; then
			__="/${T2[*]}/"
		else
			__=/
		fi
	elif [[ I -ne 0 ]]; then
		__="/${T2[*]}"
	else
		__=/.
	fi
}

function getlibpaths {
	local FILE=$1 LINE

	[[ -f $FILE && -r $FILE ]] || return

	while read LINE; do
		case "$LINE" in
		/*)
			LIBPATHS[${#LIBPATHS[@]}]=$LINE
			;;
		include\ *)
			local PATTERN=${LINE##include+([[:blank:]])}

			if [[ $PATTERN != /* ]]; then
				getabspath "$FILE"
				PATTERN=${__%/*}/${PATTERN}
			fi

			while read LINE; do
				getlibpaths "$LINE"
			done < <(compgen -G "$PATTERN")
			;;
		esac
	done < "$FILE"
}

function main {
	# Check arguments.

	[[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]] && {
		echo "Usage: $0 <partstring> [partstring2, ...]"
		return 1
	}

	# Prepare patterns.

	local A
	local -a IPATTERNS=(-iname "*$1*")

	for A in "${@:2}"; do
		IPATTERNS=("${IPATTERNS[@]}" -and -iname "*$A*")
	done

	# Prepare paths.

	getlibpaths "/etc/ld.so.conf"

	# Make list unique.

	local -a T=("${!LIBPATHS[@]}")
	local -i I=0 J C=${#T[@]} D=0
	for (( ; I < C; ++I )); do
		for (( J = I + 1; J < C; ++J )); do
			[[ ${LIBPATHS[T[I]]} = "${LIBPATHS[T[J]]}" ]] && {
				unset LIBPATHS\[T\[J\]\] T\[J\]
				(( ++D ))
			}
		done
		[[ D -gt 0 ]] && {
			T=("${T[@]:I + 1}")
			(( C -= D + I + 1, I = -1, D = 0 ))
		}
	done

	# Remove unusable entries.

	for I in "${!LIBPATHS[@]}"; do
		[[ ${LIBPATHS[I]} == *([[:blank:]]) ]] && unset 'LIBPATHS[I]'
	done

	# Remove directories that do not exist, are not readable, or is not executable.

	for I in "${!LIBPATHS[@]}"; do
		[[ -d "${LIBPATHS[I]}" && -r "${LIBPATHS[I]}" && -x "${LIBPATHS[I]}" ]] || unset 'LIBPATHS[I]'
	done

	# Find.

	[[ ${#LIBPATHS[@]} -gt 0 ]] && find "${LIBPATHS[@]}" -maxdepth 1 -xtype f "${IPATTERNS[@]}" 2>/dev/null
}

# Start.

main "$@"
