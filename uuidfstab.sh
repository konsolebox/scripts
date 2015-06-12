#!/bin/bash

# ----------------------------------------------------------------------

# uuidfstab
#
# Converts device paths in a fstab file to UUID forms.
#
# Usage: uuidfstab[.sh] [--] fstab_file [output]
#        uuidfstab[.sh] <-h | --help | -V | --version>
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 12, 2015

# ----------------------------------------------------------------------

VERSION=2015-06-12

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

	local FSTAB_FILE=$1 SPECIFIED_OUTPUT=$2 LINE DEVICE TEMP_FILE ID OUTPUT_FILE

	if [[ -z ${SPECIFIED_OUTPUT} ]]; then
		TEMP_FILE=$(mktemp)
		[[ -z ${TEMP_FILE} || ! -f ${TEMP_FILE} ]] && fail "Unable to create temporary file."
		[[ -w ${TEMP_FILE} ]] || fail "Temporary file can't be written into."
		OUTPUT_FILE=${TEMP_FILE}
	elif [[ ${SPECIFIED_OUTPUT} == - ]]; then
		SPECIFIED_OUTPUT=/dev/stdout
		OUTPUT_FILE=/dev/stdout
	else
		: >> "${SPECIFIED_OUTPUT}" || fail "Unable to create file or write to file: ${SPECIFIED_OUTPUT}"
		OUTPUT_FILE=${SPECIFIED_OUTPUT}
	fi

	shopt -s extglob

	[[ -f ${FSTAB_FILE} && -r ${FSTAB_FILE} ]] || fail "Fstab file ${FSTAB_FILE} does not exist or is not readable."

	log "Processing ${FSTAB_FILE} and writing output to ${OUTPUT_FILE}."

	while read -r LINE; do
		DEVICE=${LINE%%+([[:space:]])*}
		PRINTED=false

		if [[ ${DEVICE} == /dev/* ]]; then
			ID=$(blkid "${DEVICE}" -s UUID -o value)

			if [[ -n ${ID} ]]; then
				echo "# ${DEVICE} = ${ID}" >&3
				echo "${LINE/${DEVICE}/UUID=${ID}}" >&3
				PRINTED=true
			fi
		fi

		[[ ${PRINTED} = false ]] && echo "${LINE}" >&3
	done < "${FSTAB_FILE}" 3> "${OUTPUT_FILE}" || fail "Failed."

	if [[ -z ${SPECIFIED_OUTPUT} ]]; then
		log "Saving output from ${TEMP_FILE} to ${FSTAB_FILE}."
		cat "${TEMP_FILE}" > "${FSTAB_FILE}" || fail "Unable to save modifications to fstab file."
		rm "${TEMP_FILE}" || log "Warning: Failed to delete temporary file: ${TEMP_FILE}" >&2
	fi

	log "Done."

	return 0
}

main "$@"
