#!/bin/bash

# ----------------------------------------------------------------------

# tcpdump-master
#
# The script is a tcpdump service starter and manager.  It can also
# automatically delete files older than C days, and reduce the size of
# the main log file if it's already larger than N bytes.
#
# The script was originally a solution for this thread in LQ:
# https://www.linuxquestions.org/questions/linux-networking-3/rotating-capture-files-using-tcpdump-800385/
#
# Note: It is recommended to use Bash version 4.3 or newer to prevent
# crashes related to race conditions in catching signals and handling
# traps.
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 27, 2018

# Copyright-related details:
#
# The author (konsolebox) explicitly disclaims copyright of this file in all
# jurisdictions which recognize such a disclaimer.  In such jurisdictions,
# this software is released into the Public Domain.
#
# In jurisdictions which do not recognize Public Domain property (e.g. Germany as of
# 2010), this software is Copyright (c) 2007-2010 by Baptiste Lepilleur, and is
# released under the terms of the MIT License (see below).
#
# In jurisdictions which recognize Public Domain property, the user of this
# software may choose to accept it either as 1) Public Domain, 2) under the
# conditions of the MIT License (see below), or 3) under the terms of dual
# Public Domain/MIT License conditions described here, as they choose.
#
# The MIT License is about as close to Public Domain as a license can get, and is
# described in clear, concise terms at:
#
#    http://en.wikipedia.org/wiki/MIT_License
#
# The full text of the MIT License follows:
#
# ========================================================================
# Copyright (c) 2018 konsolebox
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ========================================================================
# (END LICENSE TEXT)
#
# The MIT license is compatible with both the GPL and commercial
# software, affording one all of the rights of Public Domain with the
# minor nuisance of being required to keep the above copyright notice
# and license text in the source code. Note also that by accepting the
# Public Domain "license" you can re-license your copy using whatever
# license you like.

# ----------------------------------------------------------------------

if [ -z "${BASH_VERSION}" ]; then
	echo "You need Bash to run this script."
	exit 1
fi

shopt -s extglob

# Settings

LOG_DIR='/var/log/tcpdump'

MAIN_LOG_FILE='main.log'
MAIN_LOG_FILE_MAX_SIZE=$(( 20 * 1024 * 1024 ))  ## Bytes.  File is reduced when this size is reached.
MAIN_LOG_FILE_ALLOWANCE=$(( 1 * 1024 * 1024 ))  ## Bytes.  This is the extra space given when file is reduced.
MAIN_LOG_CHECK_INTERVALS=300                    ## Seconds.  Recommended: >= 300

TCPDUMP='/usr/sbin/tcpdump'
TCPDUMP_ARGS=(-C 1)         ## Customize arguments here e.g. (-C 1 "another with spaces")
TCPDUMP_CAPTURE_FILE_PREFIX='capture-'
TCPDUMP_CAPTURE_FILE_SUFFIX=''
TCPDUMP_CHECK_INTERVALS=60  ## Seconds

DAYS_OLD=14        ## Days
DD_BLOCK_SIZE=512  ## Bytes
TEMP_DIR='/var/tmp'

# Other runtime variables.  Do not touch.

CURRENT_DATE=''
TCPDUMP_PID=0
QUIT=false

# Functions

function log {
	echo "[$(date '+%F %T')] $1" >> "${MAIN_LOG_FILE}"
	echo "$1"
}

function check_tcpdump {
	[[ ${TCPDUMP_PID} -ne 0 ]] && [[ -e /proc/${TCPDUMP_PID} ]] && kill -s 0 "${TCPDUMP_PID}" 2>/dev/null
}

function start_tcpdump {
	log "Starting tcpdump."

	CURRENT_DATE=$(date +%F)
	local BASENAME=${TCPDUMP_CAPTURE_FILE_PREFIX}${CURRENT_DATE}${TCPDUMP_CAPTURE_FILE_SUFFIX}
	local EXISTING_FILES=()

	{
		if [[ BASH_VERSINFO -ge 4 ]]; then
			readarray -t EXISTING_FILES
		else
			local I=0

			while read -r LINE; do
				EXISTING_FILES[I++]=${LINE}
			done
		fi
	} < <(compgen -G "${LOG_DIR}/${BASENAME}.+([[:digit:]]).log*([[:digit:]])")

	local NEXT_SESSION=0

	if [[ ${#EXISTING_FILES[@]} -gt 0 ]]; then
		local SESSION_NUMBER

		for FILE in "${EXISTING_FILES[@]}"; do
			SESSION_NUMBER=${FILE%.log*}
			SESSION_NUMBER=${SESSION_NUMBER##*.}
			[[ ${SESSION_NUMBER} == +([[:digit:]]) && SESSION_NUMBER -ge NEXT_SESSION ]] && NEXT_SESSION=$(( SESSION_NUMBER + 1 ))
		done
	fi

	local OUTPUT_FILE=${LOG_DIR}/${BASENAME}.${NEXT_SESSION}.log
	"${TCPDUMP}" "${TCPDUMP_ARGS[@]}" -w "${OUTPUT_FILE}" &

	if [[ $? -ne 0 ]]; then
		TCPDUMP_PID=0
		return 1
	fi

	TCPDUMP_PID=$!
	disown "${TCPDUMP_PID}"
	log "PID of tcpdump: ${TCPDUMP_PID}"
	check_tcpdump
}

function start_tcpdump_loop {
	until start_tcpdump; do
		log "Error: Failed to start tcpdump.  Waiting for 20 seconds before next attempt."
		read -t 20

		if [[ ${QUIT} == true ]]; then
			log "Ending tcpdump manager script."
			exit
		fi
	done
}

function stop_tcpdump {
	log "Stopping tcpdump."
	kill "${TCPDUMP_PID}"
	sleep 1
	check_tcpdump && kill -s 9 "${TCPDUMP_PID}"
	TCPDUMP_PID=0
}

function restart_tcpdump {
	log "Restarting tcpdump."
	check_tcpdump && stop_tcpdump
	start_tcpdump_loop
}

function signal_caught_callback {
	local SIGNAL=$1
	log "Caught signal ${SIGNAL}."
	QUIT=true
}

function main {
	local CAPTURE_FILE_PATTERN FILE NEW_DATE SIZE TEMP_FILE I

	CAPTURE_FILE_PATTERN="${TCPDUMP_CAPTURE_FILE_PREFIX}[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]${TCPDUMP_CAPTURE_FILE_SUFFIX}.log*"
	[[ ${MAIN_LOG_FILE} != */* ]] && MAIN_LOG_FILE=${LOG_DIR}/${MAIN_LOG_FILE}

	log "----------------------------------------"
	log "Starting up."
	log "PID: $$"

	[[ ${MAIN_LOG_FILE_MAX_SIZE} == +([[:digit:]]) && MAIN_LOG_FILE_MAX_SIZE -gt DD_BLOCK_SIZE ]] || {
		echo "MAIN_LOG_FILE_MAX_SIZE is not valid: ${MAIN_LOG_FILE_MAX_SIZE}"
		return 1
	}

	[[ ${MAIN_LOG_FILE_ALLOWANCE} == +([[:digit:]]) && MAIN_LOG_FILE_ALLOWANCE -gt DD_BLOCK_SIZE && MAIN_LOG_FILE_ALLOWANCE -lt MAIN_LOG_FILE_MAX_SIZE ]] || {
		echo "MAIN_LOG_FILE_ALLOWANCE is not valid: ${MAIN_LOG_FILE_ALLOWANCE}"
		return 1
	}

	for S in SIGQUIT SIGINT SIGKILL SIGTERM; do
		eval "
			function catch_${S} { signal_caught_callback ${S}; }
			trap catch_${S} ${S}
		"
	done

	mkdir -p "${LOG_DIR}"
	start_tcpdump_loop

	for (( I = 1;; I = (I + 1) % 10000 )); do
		read -t 1

		[[ ${QUIT} == true ]] && break

		if (( (I % TCPDUMP_CHECK_INTERVALS) == 0 )); then
			NEW_DATE=$(date +%F)

			if [[ ${NEW_DATE} != "${CURRENT_DATE}" ]]; then
				log "A new day has come."

				if read -rd '' FILE; then
					log "Deleting ${DAYS_OLD}-days old files."

					while
						log "Deleting ${FILE}."
						rm -f -- "${FILE}"
						read -r FILE
					do
						continue
					done

					log "Done."
				fi < <(exec find "${LOG_DIR}" -name "${CAPTURE_FILE_PATTERN}" -daystart -ctime "+${DAYS_OLD}" -print0)  ## Or -mtime?

				restart_tcpdump
			fi
		fi

		if (( (I % MAIN_LOG_CHECK_INTERVALS) == 0 )); then
			SIZE=$(stat --printf=%s "${MAIN_LOG_FILE}")

			if [[ ${SIZE} == +([[:digit:]]) && SIZE -gt MAIN_LOG_FILE_MAX_SIZE ]]; then
				log "Reducing log data in ${MAIN_LOG_FILE}."
				TEMP_FILE=${TEMP_DIR}/tcpdump-${RANDOM}.tmp
				SKIP=$(( (SIZE - (MAIN_LOG_FILE_MAX_SIZE - MAIN_LOG_FILE_ALLOWANCE)) / DD_BLOCK_SIZE ))

				if
					dd "bs=${DD_BLOCK_SIZE}" "skip=${SKIP}" "if=${MAIN_LOG_FILE}" "of=${TEMP_FILE}" \
					&& cat "${TEMP_FILE}" > "${MAIN_LOG_FILE}" \
					&& rm -f "${TEMP_FILE}"
				then
					log "Done."
				else
					log "Failed.  Something went wrong."
				fi
			fi
		fi
	done

	log "Shutting down."
	check_tcpdump && stop_tcpdump
	log "----------------------------------------"
}

# Start.

main
