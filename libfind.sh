#!/bin/bash

# ----------------------------------------------------------

# libfind.sh
#
# Finds library files directories specified in /etc/ld.so.conf.
#
# If no directory paths are found, search in /lib, /usr/lib and
# /usr/local/lib instead.  Those can be changed by changing the
# values of DEFAULT_LIBPATHS.
#
# Usage: libfind[.sh] keyword [keyword2 ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 8, 2015

# ----------------------------------------------------------

# Check Bash version.

[[ $BASH_VERSINFO -ge 3 ]] || {
	echo "This script requires Bash version 3.0 or newer."
	return 1
}

# The variable.

LIBPATHS=()

# Default paths to search from.

DEFAULT_LIBPATHS=(/lib /usr/lib /usr/local/lib)

# Enable extended patterns.

shopt -s extglob

# Functions

function getabspath {
	local T1 T2=() I=0 IFS=/

	if [[ $1 == /* ]]; then
		read -a T1 <<< "$1"
	else
		read -a T1 <<< "$PWD/$1"
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

	case $1 in
	*/)
		(( I )) && __="/${T2[*]}/" || __=/
		;;
	*)
		(( I )) && __="/${T2[*]}" || __=/.
		;;
	esac
}

function getlibpaths {
	[[ -f $1 && -r $1 ]] || return

	while read __; do
		case $__ in
		/*)
			LIBPATHS[${#LIBPATHS[@]}]=$__
			;;
		include\ *)
			local PATTERN=${__##include+([[:blank:]])}

			if [[ $PATTERN != /* ]]; then
				getabspath "$1"
				PATTERN=${__%/*}/${PATTERN}
			fi

			while read __; do
				getlibpaths "$__"
			done < <(compgen -G "$PATTERN")
			;;
		esac
	done < "$1"
}

function main {
	local __

	# Check arguments.

	[[ $# -eq 0 || $1 == '-h' || $1 == '--help' ]] && {
		echo "Usage: $0 keyword [keyword2 ...]"
		return 1
	}

	# Prepare patterns.

	local IPATTERNS=(-iname "*$1*"); shift

	for __; do
		IPATTERNS=("${IPATTERNS[@]}" -and -iname "*$__*")
	done

	# Prepare paths.

	getlibpaths '/etc/ld.so.conf'

	if [[ ${#LIBPATHS[@]} -eq 0 ]]; then
		# Use default list.

		LIBPATHS=("${DEFAULT_LIBPATHS[@]}")
	else
		# Make list unique.

		local T=("${!LIBPATHS[@]}") I=0 J C=${#T[@]} D=0

		for (( ; I < C; ++I )); do
			for (( J = I + 1; J < C; ++J )); do
				[[ ${LIBPATHS[${T[I]}]} == "${LIBPATHS[${T[J]}]}" ]] && {
					unset "LIBPATHS[${T[J]}]" 'T[J]'
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
	fi

	# Remove directories that do not exist, are not readable, or is not executable.

	for I in "${!LIBPATHS[@]}"; do
		[[ -d ${LIBPATHS[I]} && -r ${LIBPATHS[I]} && -x ${LIBPATHS[I]} ]] || unset 'LIBPATHS[I]'
	done

	# Find.

	[[ ${#LIBPATHS[@]} -gt 0 ]] && find "${LIBPATHS[@]}" -maxdepth 1 -xtype f "${IPATTERNS[@]}" 2>/dev/null
}

# Start.

main "$@"
