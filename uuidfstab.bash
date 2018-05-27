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
# May 27, 2018

# ----------------------------------------------------------------------

VERSION=2018-05-27

function log {
	printf '%s\n' "$@" >&2
}

function show_usage_and_exit {
	log "Converts device paths in a fstab file to UUID forms.

Usage: $0 [--] fstab_file [output]
       $0 <-h | --help | -V | --version>

Notes:
1) If output is not specified, uuidfstab would write changes to a temporary
   file and then save it to fstab_file instead.
2) Specifying '-' for the output specifies /dev/stdout.
3) All messages coming from uuidfstab are sent to file descriptor 2 or
   /dev/stderr.

Disclaimer: This tool comes with no warranty."

	exit 1
}

function fail {
	log "$@"
	exit 1
}

function main {
	local __

	for __; do
		case $__ in
		--)
			break
			;;
		-V|--version)
			log "${VERSION}"
			exit 1
			;;
		-h|--help)
			show_usage_and_exit
			;;
		esac
	done

	if [[ $# -ne 1 && $# -ne 2 ]]; then
		echo "Invalid number of arguments." >&2
		show_usage_and_exit
	fi

	local fstab_file=$1 specified_output=$2 temp_file output_file

	if [[ -z ${specified_output} ]]; then
		temp_file=$(mktemp)
		[[ -z ${temp_file} || ! -f ${temp_file} ]] && fail "Unable to create temporary file."
		[[ -w ${temp_file} ]] || fail "Temporary file can't be written into."
		output_file=${temp_file}
	elif [[ ${specified_output} == - ]]; then
		specified_output=/dev/stdout
		output_file=/dev/stdout
	else
		: >> "${specified_output}" || fail "Unable to create file or write to file: ${specified_output}"
		output_file=${specified_output}
	fi

	shopt -s extglob

	[[ -f ${fstab_file} && -r ${fstab_file} ]] || fail "Fstab file ${fstab_file} does not exist or is not readable."

	log "Processing ${fstab_file} and writing output to ${output_file}."

	local line device printed id

	while read -r line; do
		device=${line%%+([[:space:]])*}
		printed=false

		if [[ ${device} == /dev/* ]]; then
			id=$(blkid "${device}" -s UUID -o value)

			if [[ -n ${id} ]]; then
				echo "# ${device} = ${id}" >&3
				echo "${line/${device}/UUID=${id}}" >&3
				printed=true
			fi
		fi

		[[ ${printed} = false ]] && echo "${line}" >&3
	done < "${fstab_file}" 3> "${output_file}" || fail "Failed."

	if [[ -z ${specified_output} ]]; then
		log "Saving output from ${temp_file} to ${fstab_file}."
		cat "${temp_file}" > "${fstab_file}" || fail "Unable to save modifications to fstab file."
		rm "${temp_file}" || log "Warning: Failed to delete temporary file: ${temp_file}" >&2
	fi

	log "Done."

	return 0
}

main "$@"
