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
# I recommended running the script with Bash version 4.3 or newer to
# prevent crashes related to race conditions in catching signals and
# handling traps.
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 3, 2019

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
# Copyright (c) 2019 konsolebox
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

# Configuration variables

LOG_DIR='/var/log/tcpdump'

MAIN_LOG_FILE='main.log'                        ## ${LOG_DIR}/ is prepended to this if it's in
                                                ## basename form.
MAIN_LOG_FILE_MAX_SIZE=$(( 20 * 1024 * 1024 ))  ## Bytes.  File gets truncated to this size.
MAIN_LOG_FILE_ALLOWANCE=$(( 1 * 1024 * 1024 ))  ## Bytes.  It's an extra space given to the file so
                                                ##         it can add more content before reaching
                                                ##         max size again.
MAIN_LOG_CHECK_INTERVALS=300                    ## Seconds.  Recommended: >= 300

TCPDUMP='/usr/sbin/tcpdump'
TCPDUMP_ARGS=(-C 1)                     ## Add extra tcpdump arguments here.
                                        ## E.g. TCPDUMP_ARGS=(-C 1 -i ens33)
TCPDUMP_CAPTURE_FILE_PREFIX='capture-'
TCPDUMP_CAPTURE_FILE_SUFFIX=''
TCPDUMP_CHECK_INTERVALS=60              ## Seconds

DAYS_OLD=14        ## Days
DD_BLOCK_SIZE=512  ## Bytes
TEMP_DIR='/var/tmp'

# Other runtime variables

CURRENT_DATE=
QUIT=false
SLEEP_FD=
TCPDUMP_PID=0

# Functions

if [[ BASH_VERSINFO -ge 5 || (BASH_VERSINFO -eq 4 && BASH_VERSINFO[1] -ge 2) ]]; then
	function get_date {
		printf -v __ '%(%F)T'
	}

	function get_date_and_time {
		printf -v __ '%(%F %T)T'
	}
else
	function get_date {
		__=$(date '+%F')
	}

	function get_date_and_time {
		__=$(date '+%F %T')
	}
fi

function log {
	get_date_and_time
	printf "[%s] %s\n" "$__" "$1" >> "${MAIN_LOG_FILE}"
	printf "* %s\n" "$1"
}

function log_divider {
	log "----------------------------------------"
}

function log_error {
	log "[ERROR] $1"
}

function log_final_error {
	log_error "$1"
	log_divider
	exit 1
}

function log_stderr {
	printf "* %s\n" "$1" >&2
}

if [[ $(type -t sleep) != builtin ]]; then
	SLEEP_FD=9
	eval "exec ${SLEEP_FD}<> <(:)"  ## Sleep trick discovered by nai

	function sleep {
		if [[ $1 == +([[:digit:]]) && $1 -gt 0 ]]; then
			if [[ -n ${SLEEP_FD} ]]; then
				local start=${SECONDS}
				read -u "${SLEEP_FD}" -t "$1"
				true

				if [[ SECONDS -eq start ]]; then
					[[ SLEEP_FD -ne 0 ]] && eval "exec ${SLEEP_FD}<&-"

					if [[ SLEEP_FD -ne 0 && -t 0 ]]; then
						SLEEP_FD=0
					else
						unset SLEEP_FD
					fi

					sleep "$1"
				fi
			elif type -P sleep >/dev/null; then
				function sleep {
					command sleep "$1"
				}

				command sleep "$1"
			else
				log "Can't sleep."
				false
			fi
		fi
	}
fi

function check_tcpdump {
	[[ TCPDUMP_PID -ne 0 ]] && kill -s 0 "${TCPDUMP_PID}" 2>/dev/null
}

function start_tcpdump {
	log "Starting tcpdump."
	get_date
	CURRENT_DATE=$__
	local basename=${TCPDUMP_CAPTURE_FILE_PREFIX}${CURRENT_DATE}${TCPDUMP_CAPTURE_FILE_SUFFIX}
	local existing_files=()

	{
		if [[ BASH_VERSINFO -ge 4 ]]; then
			readarray -t existing_files
		else
			local i=0 line

			while read -r line; do
				existing_files[i++]=${line}
			done
		fi
	} < <(compgen -G "${LOG_DIR}/${basename}.+([[:digit:]]).log*([[:digit:]])")

	local next_session=0

	if [[ ${#existing_files[@]} -gt 0 ]]; then
		local session_number file

		for file in "${existing_files[@]}"; do
			session_number=${file%.log*}
			session_number=${session_number##*.}

			if [[ ${session_number} == +([[:digit:]]) && session_number -ge next_session ]]; then
				next_session=$(( session_number + 1 ))
			fi
		done
	fi

	local output_file=${LOG_DIR}/${basename}.${next_session}.log
	"${TCPDUMP}" "${TCPDUMP_ARGS[@]}" -w "${output_file}" &

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
		log_error "Failed to start tcpdump.  Waiting for 20 seconds before next attempt."
		sleep 20

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
	local signal=$1
	log "Caught signal ${signal}."
	QUIT=true
}

function main {
	local capture_file_pattern="${TCPDUMP_CAPTURE_FILE_PREFIX}[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]${TCPDUMP_CAPTURE_FILE_SUFFIX}.log*"
	[[ ${MAIN_LOG_FILE} != */* ]] && MAIN_LOG_FILE=${LOG_DIR}/${MAIN_LOG_FILE}

	: >> "${MAIN_LOG_FILE}" || {
		log_stderr "Unable to create or write to main log file '${MAIN_LOG_FILE}'."
		return 1
	}

	log_divider
	log "Starting up."
	log "PID: $$"

	[[ -d ${LOG_DIR} ]] || log_final_error "Main log directory '${LOG_DIR}' is not a directory."
	[[ -w ${LOG_DIR} ]] || log_final_error "Main log directory '${LOG_DIR}' is not writable."

	[[ ${MAIN_LOG_FILE_MAX_SIZE} == +([[:digit:]]) && MAIN_LOG_FILE_MAX_SIZE -gt DD_BLOCK_SIZE ]] || {
		log_final_error "MAIN_LOG_FILE_MAX_SIZE is not valid: ${MAIN_LOG_FILE_MAX_SIZE}"
	}

	[[ ${MAIN_LOG_FILE_ALLOWANCE} == +([[:digit:]]) && MAIN_LOG_FILE_ALLOWANCE -gt DD_BLOCK_SIZE && MAIN_LOG_FILE_ALLOWANCE -lt MAIN_LOG_FILE_MAX_SIZE ]] || {
		log_final_error "MAIN_LOG_FILE_ALLOWANCE is not valid: ${MAIN_LOG_FILE_ALLOWANCE}"
	}

	local s

	for s in SIGHUP SIGQUIT SIGINT SIGTERM; do
		eval "
			function catch_${s} { signal_caught_callback ${s}; }
			trap catch_${s} ${s}
		"
	done

	mkdir -p -- "${LOG_DIR}"
	start_tcpdump_loop
	local i

	for (( i = 1;; i = (i + 1) % 10000 )); do
		[[ ${QUIT} != true ]] && sleep 1 && [[ ${QUIT} != true ]] || break

		if (( (i % TCPDUMP_CHECK_INTERVALS) == 0 )); then
			get_date

			if [[ ${CURRENT_DATE} != "$__" ]]; then
				log "A new day has come."
				local file

				if IFS= read -rd '' -u8 file; then
					log "Deleting ${DAYS_OLD}-days old files."

					while
						log "Deleting ${file}."
						rm -f -- "${file}"
						IFS= read -rd '' -u8 file
					do
						continue
					done

					log "Done."
				fi 8< <(
					exec find "${LOG_DIR}" -name "${capture_file_pattern}" -daystart \
						-ctime "+${DAYS_OLD}" -print0  ## Or perhaps -mtime.
				)

				restart_tcpdump
			fi
		fi

		if (( (i % MAIN_LOG_CHECK_INTERVALS) == 0 )); then
			local size=$(stat --printf=%s "${MAIN_LOG_FILE}")

			if [[ ${size} == +([[:digit:]]) && size -gt MAIN_LOG_FILE_MAX_SIZE ]]; then
				log "Reducing log data in ${MAIN_LOG_FILE}."
				local temp_file=${TEMP_DIR}/tcpdump-${RANDOM}.tmp
				local skip=$(( (size - (MAIN_LOG_FILE_MAX_SIZE - MAIN_LOG_FILE_ALLOWANCE)) / DD_BLOCK_SIZE ))

				dd "bs=${DD_BLOCK_SIZE}" "skip=${skip}" "if=${MAIN_LOG_FILE}" "of=${temp_file}" && \
					cat "${temp_file}" > "${MAIN_LOG_FILE}" && \
						rm -f -- "${temp_file}"

				if [[ $? -eq 0 ]]; then
					log "Done."
				else
					log_error "Something failed."
				fi
			fi
		fi
	done

	log "Shutting down."
	check_tcpdump && stop_tcpdump
	[[ SLEEP_FD -gt 0 ]] && eval "exec ${SLEEP_FD}<&-"
	log_divider
}

# Start.

main
