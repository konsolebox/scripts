#!/bin/bash

# ----------------------------------------------------------

# manfind
#
# Finds manual pages in $MANPATH by keywords.
#
# Usage: manfind[.bash] keyword [keyword2 ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 27, 2018

# ----------------------------------------------------------

# Check if shell is Bash.

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

# Disable filename expansion.

set -f

# Place everything inside a main function.

function main {
	# Check arguments.

	[[ $# -eq 0 || $1 == '-h' || $1 == '--help' ]] && {
		echo "Usage: $0 keyword [keyword2 ...]"
		return 1
	}

	# Prepare iname options.

	local args=() __

	for __; do
		args=("${args[@]}" -iname "*$__*")
	done

	# Prepare paths.

	local paths=() IFS=: i=0

	for __ in $MANPATH; do
		[[ -n $__ && ":${paths[*]}:" != *":$__:"* ]] && paths[i++]=$__
	done

	# Find.

	[[ ${#paths[@]} -gt 0 ]] && find "${paths[@]}" -maxdepth 2 -xtype f -regex '.*/man[^/]+/.*' "${args[@]}" 2>/dev/null
}

# Start.

main "$@"
