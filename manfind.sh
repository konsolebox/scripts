#!/bin/bash

# ----------------------------------------------------------

# manfind
#
# Searches for manual pages based from $MANPATH.
#
# Usage: manfind[.sh] <partstring> [partstring2, ...]
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

# Enable extended patterns.

shopt -s extglob

# Place everything inside a function to keep things clean.

function main {
	# Check arguments.

	[[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]] && {
		echo "Usage: manfind <partstring> [partstring2, ...]"
		return 1
	}

	# Prepare patterns.

	local A
	local -a IPATTERNS=()

	for A; do
		IPATTERNS=("${IPATTERNS[@]}" -and -iname "*$A*.*.*")
	done

	# Prepare paths.

	local -a PATHS
	IFS=: read -r -a PATHS <<< "$MANPATH"

	# Make list entries unique.

	local -a T=("${!PATHS[@]}")
	local -i I=0 J C=${#T[@]} D=0
	for (( ; I < C; ++I )); do
		for (( J = I + 1; J < C; ++J )); do
			[[ ${PATHS[T[I]]} = "${PATHS[T[J]]}" ]] && {
				unset PATHS\[T\[J\]\] T\[J\]
				(( ++D ))
			}
		done
		[[ D -gt 0 ]] && {
			T=("${T[@]:I + 1}")
			(( C -= D + I + 1, I = -1, D = 0 ))
		}
	done

	# Remove unusable entries.

	for I in "${!PATHS[@]}"; do
		[[ "${PATHS[I]}" == *([[:blank:]]) ]] && unset 'PATHS[I]'
	done

	# Find.

	[[ ${#PATHS[@]} -gt 0 ]] && find "${PATHS[@]}" -maxdepth 2 -xtype f -regex '.*/man[^/]+/.*' "${IPATTERNS[@]}" 2>/dev/null
}

# Start.

main "$@"
