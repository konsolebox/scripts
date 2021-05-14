#!/bin/bash

# ------------------------------------------------------------
#
# killtree-lite
#
# A less poetic version of killtree
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 14, 2021
#
# ------------------------------------------------------------

set -f +o posix && shopt -s extglob || exit 1

# killtree (pid, signal = 'SIGTERM')
#
function killtree {
	if [[ $1 == -- ]]; then
		shift; list+=("$@")

		for __ do
			killtree -- $(pgrep -P "$__")
		done
	else
		local list=() IFS=$'\n' __
		killtree -- "$1"
		kill -s "${2-SIGTERM}" "${list[@]}"
	fi
}

# main (['-s', signal,] pid, ...)
#
function main {
	local sig=SIGTERM __

	if [[ $1 == -s && -n $2 ]]; then
		sig=$2
		shift 2
	fi

	for __ do
		if [[ $1 != +([[:digit:]]) ]]; then
			echo "Usage: $0 [-s signal] pid ..." >&2
			exit 1
		fi
	done

	for __ do
		killtree "$__" "${sig}"
	done
}

main "$@"
