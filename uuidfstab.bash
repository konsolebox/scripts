#!/bin/bash

# ----------------------------------------------------------------------

# uuidfstab
#
# Converts device paths in a fstab file to UUID forms.
#
# Usage: uuidfstab[.bash] [--] fstab_file [output]
#        uuidfstab[.bash] <-h | --help | -V | --version>
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 14, 2021

# ----------------------------------------------------------------------

[ -n "${BASH_VERSION}" ] || {
	echo "Bash is needed to run this script." >&2
	exit 1
}

set -f +o posix || exit 1

VERSION=2021.05.14

function log {
	printf '%s\n' "$@" >&2
}

function show_usage_and_exit {
	log "uuidfstab ${VERSION}
Converts device paths in a fstab file to UUID forms.

Usage: $0 [--] fstab_file [output_file]
       $0 <-h | --help | -V | --version>

Notes:
1) Results are saved back to the fstab_file if no output is specified.
2) If - is specified as output, results are sent to stdout instead.
3) All other messages are sent to stderr.

Disclaimer: This tool comes with no warranty."
	exit 1
}

function fail {
	log "$@"
	exit 1
}

function main {
	local non_opt_args

	while [[ $# -gt 0 ]]; do
		case $1 in
		--)
			non_opt_args=("${non_opt_args[@]}" "${@:2}")
			break
			;;
		-V|--version)
			log "${VERSION}"
			exit 1
			;;
		-h|--help)
			show_usage_and_exit
			;;
		-)
			non_opt_args=("${non_opt_args[@]}" -)
			;;
		-*)
			log "Invalid option: $1"
			;;
		*)
			non_opt_args=("${non_opt_args[@]}" "$1")
			;;
		esac

		shift
	done

	set -- "${non_opt_args[@]}"
	[[ $# -eq 0 ]] && fail "No argument specified."
	[[ $# -gt 2 ]] && fail "Too many arguments specified."

	local fstab_file=$1 output_file=("${@:2}") actual_output_file=
	[[ -e ${fstab_file} ]] || fail "File doesn't exist: ${fstab_file}"
	[[ -f ${fstab_file} ]] || fail "Not a regular file: ${fstab_file}"
	exec 3< "${fstab_file}" || fail "Failed to open '${fstab_file}' for reading."

	if [[ -z ${output_file+.} ]]; then
		log "Processing '${fstab_file}' and saving results to it."
	elif [[ ${output_file} == - ]]; then
		log "Processing '${fstab_file}' and writing results to stdout."
	else
		[[ -e ${output_file} && ! -f ${output_file} ]] && fail "Not a regular file: ${output_file}"
		log "Processing '${fstab_file}' and writing results to '${output_file}'."
	fi

	exec 3< "${fstab_file}" || fail "Failed to open '${fstab_file}' for reading."
	local line device output

	while IFS= read -ru3 line; do
		device=(${line})

		if [[ $1 == /dev/* ]]; then
			id=$(blkid "${device}" -s UUID -o value) || \
				fail "Error occurred while trying to get UUID of '${device}'."

			if [[ -n ${id} ]]; then
				output[${#output[@]}]="# ${device} = ${id}"
				output[${#output[@]}]="${line/${device}/UUID=${id}}"
				continue
			fi
		fi

		output[${#output[@]}]=${line}
	done

	exec 3<&- || fail "Failed to close '${fstab_file}'."

	if [[ -z ${output_file+.} ]]; then
		printf '%s\n' "${output[@]}" >"${fstab_file}" || \
			fail "Failed to write data to '${fstab_file}'."
	elif [[ ${output_file} == - ]]; then
		printf '%s\n' "${output[@]}"
	else
		printf '%s\n' "${output[@]}" >"${output_file}" || \
			fail "Failed to write data to '${output_file}'."
	fi

	log "Done."
	return 0
}

main "$@"
