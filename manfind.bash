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
# May 14, 2021

# ----------------------------------------------------------

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

set -f || exit 1

function main {
	[[ $# -eq 0 || $1 == -h || $1 == --help ]] && {
		echo "Usage: $0 keyword [keyword2 ...]"
		return 1
	}

	local args paths IFS=: i=0 __
	args=(); paths=()

	for __; do
		args=("${args[@]}" -iname "*$__*")
	done

	for __ in ${MANPATH}; do
		[[ -n $__ && ":${paths[*]}:" != *":$__:"* ]] && paths[i++]=$__
	done

	[[ ${#paths[@]} -gt 0 ]] && find "${paths[@]}" -maxdepth 2 -xtype f -regex '.*/man[^/]+/.*' \
		"${args[@]}" 2>/dev/null
}

main "$@"
