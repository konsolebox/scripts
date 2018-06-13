#!/bin/bash

# ----------------------------------------------------------

# killtree
#
# Sends signals to process trees with style.
#
# Usage: killtree[.bash] [options] [--] process_name_or_pid ...
#
# This script also contains reusable functions.
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 13, 2018

# ----------------------------------------------------------

# kill_tree (pid, [signal = SIGTERM])
#
# Creates a list of processes first then sends the signal to all of
# them synchronously.
#
function kill_tree {
	local LIST=("$1")
	list_children_ "$1"
	kill -s "${2-SIGTERM}" "${LIST[@]}"
}

# kill_tree_2 (pid, [signal = SIGTERM])
#
# This version sends signals to processes as it goes.
#
function kill_tree_2 {
	local list=() s=${2-SIGTERM} __
	IFS=$'\n' read -ra list -d '' < <(exec pgrep -P "$1")
	kill -s "$s" "$1"

	for __ in "${list[@]}"; do
		kill_tree_2 "$__" "$s"
	done
}

# kill_tree_3 (pid, [signal = SIGTERM])
#
# This version sends signals to child processes first before the parents.
#
function kill_tree_3 {
	local list=() s=${2-SIGTERM} __
	IFS=$'\n' read -ra list -d '' < <(exec pgrep -P "$1")

	for __ in "${list[@]}"; do
		kill_tree_3 "$__" "$s"
	done

	kill -s "$s" "$1"
}

# kill_children (pid, [signal = SIGTERM])
#
# Creates a list of child processes first then sends the signal to all
# of them synchronously.
#
function kill_children {
	local LIST=()
	list_children_ "$1"
	kill -s "${2-SIGTERM}" "${LIST[@]}"
}

# kill_children_2 (pid, [signal = SIGTERM])
#
# This version sends signals to processes as it goes.
#
function kill_children_2 {
	local list=() s=${2-SIGTERM} __
	IFS=$'\n' read -ra list -d '' < <(exec pgrep -P "$1")

	for __ in "${list[@]}"; do
		kill_tree_2 "$__" "$s"
	done
}

# kill_children_3 (pid, [signal = SIGTERM])
#
# This version sends signals to child processes first before the parents.
#
function kill_children_3 {
	local list=() s=${2-SIGTERM} __
	IFS=$'\n' read -ra list -d '' < <(exec pgrep -P "$1")

	for __ in "${list[@]}"; do
		kill_tree_3 "$__" "$s"
	done
}

# list_tree (pid)
#
# Saves list of found PIDs to array variable LIST.
#
function list_tree {
	LIST=("$1")
	list_children_ "$1"
}

# list_children (pid)
#
# Saves list of found PIDs to array variable LIST.
#
function list_children {
	LIST=()
	list_children_ "$1"
}

# list_children_ (pid)
#
function list_children_ {
	local add=() __
	IFS=$'\n' read -ra add -d '' < <(exec pgrep -P "$1")
	LIST+=("${add[@]}")

	for __ in "${add[@]}"; do
		list_children_ "$__"
	done
}

# ----------------------------------------------------------

SELF=${BASHPID-$$}
VERSION=2018-06-13

function show_help_info {
	echo "Sends signals to process trees with style.

Usage: $0 [options] [--] process_name_or_id ...

Options:
  -a, --all            Send signal to all processes.  (Default)
  -c, --children-only  Only send signals to child processes, not the
                       specified parents.
  -h, --help           Show this help message.
  -o, --one-at-a-time  Immediately send signal to process after it gets its
                       child processes enumerated.
  -r, --reverse        Send signals to child processes first before parents.
  -s, --signal signal  Specify the signal to be sent to every process.
                       The default is SIGTERM.
  -S, --simultaneous   Simultaneously send signals to all processes after they
                       get enumerated.  (Default)
  -v, --verbose        Be verbose.
  -V, --version        Show version.

The default action is to send signals to all processes simultaneously, and the
default signal is SIGTERM.

The options '--one-at-a-time', '--reverse', and '--simultaneous' can be used
together as arguments, but only the last specified option becomes effective.
The behavior also applies to '--all' and '--children-only'.  It allows
cancelling out default arguments.

killtree excludes itself from matched targets.  It also bails out if its PID
is explicitly specified as an argument.

Exit Status:
The script returns 0 only when one or more processes are processed.

Example:
$0 --children-only --reverse --signal SIGHUP 1234 zombie"
}

function fail {
	echo "$@"
	exit 1
}

function exclude_self {
	__A0=()

	for __; do
		[[ $__ != "${SELF}" ]] && __A0+=("$__")
	done
}

function main {
	local function_suffix= signal=SIGTERM targets=() tree_or_children=tree verbose=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-a|--all)
			tree_or_children=tree
			;;
		-c|--children-only)
			tree_or_children=children
			;;
		-h|--help)
			show_help_info
			return 1
			;;
		-o|--one-at-a-time)
			function_suffix='_2'
			;;
		-r|--reverse)
			function_suffix='_3'
			;;
		-s|--signal)
			signal=$2
			shift
			;;
		-S|--simultaneous)
			function_suffix=
			;;
		-v|--verbose)
			verbose=true
			;;
		-V|--version)
			echo "${VERSION}"
			return 1
			;;
		--)
			targets+=("${@:2}")
			break
			;;
		-*)
			fail "Invalid option: $1"
			;;
		*)
			targets+=("$1")
			;;
		esac

		shift
	done

	[[ ${#targets[@]} -eq 0 ]] && fail "No target specified."

	if [[ ${verbose} == true ]]; then
		function kill {
			exclude_self "${@:3}"

			if [[ ${#__A0[@]} -gt 0 ]]; then
				echo "Sending singal $2 to:" "${__A0[@]}"
				builtin kill -s "$2" "${__A0[@]}"
			else
				echo "No process to send signal to."
			fi
		}

		function log_verbose {
			echo "$@"
		}
	else
		function kill {
			exclude_self "${@:3}"
			[[ ${#__A0[@]} -gt 0 ]] && builtin kill -s "$2" "${__A0[@]}"
		}

		function log_verbose {
			:
		}
	fi

	local target_pids=() pids __

	for __ in "${targets[@]}"; do
		if [[ $__ == +([[:digit:]]) ]]; then
			[[ $__ == "${SELF}" ]] && fail "Not targetting self ($__)."
			target_pids+=("$__")
		else
			IFS=$'\n' read -ra pids -d '' < <(exec pgrep -x -- "$__")
			exclude_self "${pids[@]}"
			[[ ${#__A0[@]} -eq 0 ]] && fail "No process found from name: $__"
			log_verbose "Processes matching $__: ${__A0[@]}"
			target_pids+=("${__A0[@]}")
		fi
	done

	log_verbose "Parent targets: ${target_pids[@]}"

	local func=kill_${tree_or_children}${function_suffix}

	for __ in "${target_pids[@]}"; do
		log_verbose "Call: ${func} $__"
		"${func}" "$__" "${signal}"
	done

	return 0
}

main "$@"
