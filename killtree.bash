#!/bin/bash

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

set -f +o posix && shopt -s extglob || exit 1

# ------------------------------------------------------------------------------
#
# killtree
#
# Sends signals to process trees with style.
#
# It uses pgrep to find processes.
#
# Usage: killtree[.bash] [options] [--] [[pattern|pid][/'filter_opts']] ...
#                [// [filter_opts] [--] [[pattern|pid][/'filter_opts']] ...]
#                [// [filter_opts] [--] [[pattern|pid][/'filter_opts']] ...]
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 4, 2022
#
# ------------------------------------------------------------------------------

# kill_tree (pid, [signal = SIGTERM])
#
# Creates a list of all the processes in the hierarchy first, and then sends
# signal to all of them simultaneously.
#
function kill_tree {
	local DESCENDANTS=()
	list_descendants_inner "$1"
	kill -s "${2-SIGTERM}" "$1" "${DESCENDANTS[@]}"
}

# kill_tree_2 (pid, [signal = SIGTERM])
#
# This version sends signals to processes one at a time.  It sends signal
# to a process right after it finishes enumerating the child processes of the
# process, and then it processes the child processes if they exist, or move to
# the next process in queue.
#
function kill_tree_2 {
	local s=${2-SIGTERM} CHILDREN __
	list_children "$1"
	kill -s "$s" "$1"

	for __ in "${CHILDREN[@]}"; do
		kill_tree_2 "$__" "$s"
	done
}

# kill_tree_3 (pid, [signal = SIGTERM])
#
# This version does reverse mode.  It sends signals to child processes first
# before the parents.
#
function kill_tree_3 {
	local s=${2-SIGTERM} CHILDREN __
	list_children "$1"

	for __ in "${CHILDREN[@]}"; do
		kill_tree_3 "$__" "$s"
	done

	kill -s "$s" "$1"
}

# kill_descendants (pid, [signal = SIGTERM])
#
# Same as kill_tree, but it only sends signals to the descendants of the
# specified target.
#
function kill_descendants {
	local DESCENDANTS=()
	list_descendants_inner "$1"
	[[ ${#DESCENDANTS[@]} -gt 0 ]] && kill -s "${2-SIGTERM}" "${DESCENDANTS[@]}"
}

# kill_descendants_2 (pid, [signal = SIGTERM])
#
# Same as kill_tree_2, but it only sends signals to the descendants of the
# specified target.
#
function kill_descendants_2 {
	local s=${2-SIGTERM} CHILDREN __
	list_children "$1"

	for __ in "${CHILDREN[@]}"; do
		kill_tree_2 "$__" "$s"
	done
}

# kill_descendants_3 (pid, [signal = SIGTERM])
#
# Same as kill_tree_3, but it only sends signals to the descendants of the
# specified target.
#
function kill_descendants_3 {
	local s=${2-SIGTERM} CHILDREN __
	list_children "$1"

	for __ in "${CHILDREN[@]}"; do
		kill_tree_3 "$__" "$s"
	done
}

# kill_children (pid, [signal = SIGTERM])
#
# Sends signals to direct descendants of specified target.
#
function kill_children {
	local CHILDREN
	list_children "$1"
	kill -s "${2-SIGTERM}" "${CHILDREN[@]}"
}

# list_tree (pid)
#
# Saves a list of found PIDs that composes the hierarchy of the specified PID
# including the PID to array variable TREE.
#
function list_tree {
	local DESCENDANTS=()
	list_descendants_inner "$1"
	TREE=("$1" "${DESCENDANTS[@]}")
}

# list_descendants (pid)
#
# Saves list of found PIDs that are descendants of specified PID to array
# variable DESCENDANTS.
#
function list_descendants {
	DESCENDANTS=()
	list_descendants_inner "$1"
}

# list_descendants_inner (pid)
#
# Inner recursive function of list_descendants().  It doesn't initialize the
# DESCENDANTS variable.
#
function list_descendants_inner {
	local CHILDREN __
	list_children "$1"
	DESCENDANTS+=("${CHILDREN[@]}")

	for __ in "${CHILDREN[@]}"; do
		list_descendants_inner "$__"
	done
}

# list_children (pid)
#
# Saves list of found PIDs that are direct descendants of specified PID to array
# variable CHILDREN.
#
function list_children {
	IFS=$'\n' read -ra CHILDREN -d '' < <(exec pgrep -P "$1")
}

# ------------------------------------------------------------------------------

ASK=false
ASK_ONCE=false
EXCLUDED_SELF=false
FILTER_EUIDS=()
FILTER_EXACT=()
FILTER_EXACT_DEFAULT=false
FILTER_EXACT_SUPER=
FILTER_GROUPS=()
FILTER_IGNORE_CASE=()
FILTER_IGNORE_CASE_DEFAULT=false
FILTER_IGNORE_CASE_SUPER=
FILTER_NSLIST=()
FILTER_NS=()
FILTER_PGROUPS=()
FILTER_SESSION=()
FILTER_TERMINAL=()
FILTER_UIDS=()
HAS_GEN_FILTERS=()
IFS=$' \t\r\n'
INITIAL_TARGET_PIDS=()
LAST_PRI_TARGET_ID=0
LAST_SEC_TARGET_ID=0
LAST_TER_TARGET_ID=0
PRETEND=false
SEC_FILTER_ARGS=()
SEC_FILTER_ID=0
SEC_FILTER_INDICES=()
SEC_FILTER_LENGTHS=()
SEC_FILTER_PIDS=()
SEC_GLOBAL_ID=0
SELF=${BASHPID-$$}
TARGETS=()
TARGET_ID=0
TER_FILTER_ARGS=()
TER_FILTER_ID=0
TER_FILTER_INDICES=()
TER_FILTER_LENGTHS=()
TER_FILTER_PIDS=()
TER_GLOBAL_ID=0
VERBOSE=false
VERSION=2022.05.04

function show_help_info {
	echo "killtree ${VERSION}

Sends signals to process trees with style.

Usage: killtree[.bash] [options] [--] [[pattern|pid][/'filter_opts']] ...
               [// [filter_opts] [--] [[pattern|pid][/'filter_opts']] ...]
               [// [filter_opts] [--] [[pattern|pid][/'filter_opts']] ...]

This script uses pgrep.  Expansion of pattern depends on how pgrep expands it.
See pgrep(1).  To prevent a pattern from being interpreted as a PID, place it
around parentheses.  E.g. '(1234)'.

Basic Options:

  -a, --ask            Ask before sending a signal to each process.  PIDs are
                       resolved to their command names in prompt if the system
                       is Linux.  Verbose mode makes it show long commands
                       instead of the basic \"comm\" form.
  -A, --ask-once       Same as '--ask', but only do it once on every major set
                       of processes.  This can only be used with
                       '--simultaneous' and '--union'.
  -h, --help           Show this help message and exit.
  -H, --ignore-sighup  Catch SIGHUP signal and ignore it.
  -P, --pretend        Do no actually send signals.  It's sensible to use it
                       with '--verbose'.
  -q, --quiet          Do not show warnings and info.  It negates verbose mode.
  -s, --signal signal  Specify the signal to be sent to every process.
                       The default is SIGTERM.
  -<signal>            Shortcut version of '-s'.  Signal can only be numeric.
  -v, --verbose        Show verbose messages.  It negates quiet mode.
  -V, --version        Show version and exit.

Filter Options:

  -e, --euid euid,...     Only match processes with mentioned effective user ID.
  -g, --group gid,...     Only match processes with mentioned real group ID.
  -i, --ignore-case       Make matching of processes case-insensitive.
  -I, --no-ignore-case    Do not make matching of processes case-insensitive.
  -n, --ns pid            Only match processes that belong to same namespace as
                          PID.  This may not be supported by pgrep or system.
  -N, --nslist name,...   Limit the namespaces to match processes with when
                          using '--ns'.  Available namespaces are 'ipc', 'mnt',
                          'net', 'pid', 'user', and 'uts'.  This may not be
                          supported by pgrep or the system.
  -p, --pgroup pgid,...   Only match processes with mentioned process group ID.
  -u, --uid uid,...       Only match processes with mentioned real user ID.
  -z, --session sid,...   Only match processes with mentioned session ID.
  -T, --terminal tty,...  Only match processes with mentioned controlling
                          terminal.
  -x, --exact             Match process names in an exact manner.
  -X, --no-exact          Do not match process names in an exact manner.

Superglobal Filter Options:

  -Gi, --global-ignore-case     Superglobal version of '--ignore-case'.
  -GI, --global-no-ignore-case  Superglobal version of '--no-ignore-case'.
  -Gx, --global-exact           Superglobal version of '--exact'.
  -GX, --global-no-exact        Superglobal version of '--no-exact'.

  Exact mode by default is set to ${FILTER_EXACT_DEFAULT}.
  Ignore-case mode by default is set to ${FILTER_IGNORE_CASE_DEFAULT}.

Target Options:

  -c, --children[-only]     Only send signals to direct child processes.
  -d, --descendants[-only]  Only send signals to descendant processes.
  -t, --tree                Send signals to all processes in a tree including
                            the initial parent.  (Default)

Strategy Options:

  -o, --one-at-a-time  Immediately send signal to a process in a tree after
                       enumerating the process' child processes.
  -r, --reverse        Send signals to child processes first before parents in a
                       tree.
  -S, --simultaneous   Simultaneously send signals to all processes in a tree
                       after they get enumerated.  (Default)
  -U, --unify          Uniquely gather all PIDs in every tree of every specified
                       PID before sending signals to all of them at once.  The
                       options '--children' and '--descendants' are still
                       respected when generating targets in every tree, but the
                       initial parent targets of those trees won't get exempted
                       from being targetted if they are part of another initial
                       target's tree, even when one of those options is in
                       effect.

Filtering Details

  Filtering happens in three phrases.  The first phase collects and filters
  initial parent targets of trees.  The second phase collects and filters child
  processes.  The third phase finally, selects which processes to actually send
  signals to.

  Each phase is configured separately with their own filters and/or
  patterns/PIDs, and each phase configuration is separated by '//'.

  Filter options generally can be declared global or pattern/pid-specific.
  Global options affect how all patterns behave for a specific phase, while
  pattern/PID-specific options are the most basic, and they affect a single
  matching set criteria.  Some filter options have superglobal versions which
  can affect all phases.  Global filters override superglobal filters, and
  pattern/PID-specific filters override global filters.

  Each pattern/PID-filter-opts pair produces their own set of matched PIDs and
  doesn't affect other pairs.  All PIDs matched by all pairs are unified to a
  single set.  If no pattern/PID-filter-opts pair is specified, the global
  filter options are used instead.

  Specifying global filter options and/or specifying pattern/PID-filter-opts is
  only required in the first phase where initial targets are generated.  When
  no filtering expression is specified in other phases, no other extra filtering
  happens.

  Using '--ns' and '--nslist' to match processes may not work if
  namespace-related features are not supported by the system, or the feature
  itself is not supported by pgrep.  Support for these features was added in
  procps-ng-3.3.9.  It may also be not included during pgrep's build time.

Target Mode and Strategy Details

  The default action is to send signals to all processes simultaneously.

  If '--one-at-a-time', '--reverse', '--simultaneous', and '--unify' are used
  together, only the last specified option becomes effective.  The behavior
  applies to '--children', '--descendants', and '--tree' as well.  It allows
  cancelling out default arguments.

  When the '--children' option is in effect, the options '--one-at-a-time',
  '--reverse', and '--simultaneous' are virtually the same since targets belong
  to only one level.

Other Details

  killtree excludes itself from matched targets.  It also prints a warning
  message if its own PID is specified.

  Just like pgrep, killtree also silently ignores specified processes that don't
  exist.

Exit Status

  The script returns 0 only when one or more processes are processed.

Examples

  killtree --descendants --reverse --signal SIGKILL --exact -- 1234 zombie
  killtree --unify --terminal tty5 --signal SIGHUP // // --exact bash"
}

function log_info {
	printf '%s\n' "$@"
}

function log_warning {
	printf 'Warning: %s\n' "$@" >&2
}

function log_verbose {
	printf '%s\n' "$@"
}

function fail {
	printf '%s\n' "$@" >&2
	exit 2
}

function check_if_valid_name_or_id_list_arg {
	local opt=$1 arg=$2 has_entry=false IFS=, __
	[[ ${arg} ]] || fail "Invalid empty argument to '${opt}'."

	for __ in ${arg}; do
		if [[ ${arg} ]]; then
			[[ ${arg} != @(+([[:digit:]])|+([[:lower:]])*([[:lower:][:digit:]-])) ]] && \
				log_warning "Username or group name argument to '${opt}' may be invalid: $__"

			has_entry=true
		fi
	done

	[[ ${has_entry} == false ]] && \
		fail "Specified list argument to '${opt}' is empty: ${arg}"
	[[ ${arg} == @(,*|*,,*|*,) ]] && \
		log_warning "Ignoring empty elements in list argument to '${opt}': ${arg}"
}

function check_if_valid_id_list_arg {
	local opt=$1 arg=$2 has_entry=false IFS=, __
	[[ ${arg} ]] || fail "Invalid empty argument to '${opt}'."

	for __ in ${arg}; do
		if [[ ${arg} ]]; then
			[[ ${arg} != +([[:digit:]]) ]] && \
				fail "Invalid ID argument to '${opt}': $__"

			has_entry=true
		fi
	done

	[[ ${has_entry} == false ]] && \
		fail "Specified list argument to '${opt}' is empty: ${arg}"
	[[ ${arg} == @(,*|*,,*|*,) ]] && \
		log_warning "Ignoring empty elements in list argument to '${opt}': ${arg}"
}

function check_if_valid_nslist_arg {
	local opt=$1 arg=$2 IFS=, __

	for __ in ${arg}; do
		if [[ ${arg} ]]; then
			[[ ${arg} == @(ipc|mnt|net|pid|user|uts) ]] || \
				fail "Invalid namespace argument to '${opt}': $__" \
						"Expecting 'ipc', 'mnt', 'net', 'pid', 'user', or 'uts'."

			has_entry=true
		fi
	done

	[[ ${has_entry} == false ]] && \
		fail "Specified list argument to '${opt}' is empty: ${arg}"
	[[ ${arg} == @(,*|*,,*|*,) ]] && \
		log_warning "Ignoring empty elements in list argument to '${opt}': ${arg}"
}

function check_if_valid_pid_arg {
	[[ $2 == +([[:digit:]]) ]] || fail "Invalid PID argument to '$1': $2"
}

function check_if_not_empty_arg {
	[[ $2 ]] || fail "Invalid empty argument to '$1'."
}

function warn_excluding_self {
	if [[ ${VERBOSE} == true || ${EXCLUDED_SELF} == false ]]; then
		log_warning "Excluding self ($__) from matches."
		EXCLUDED_SELF=true
	fi
}

function exclude_self {
	__A0=()
	local __

	for __; do
		[[ $__ != "${SELF}" ]] && __A0+=("$__") || warn_excluding_self
	done
}

function get_opt_and_optarg {
	local optional=false

	if [[ $1 == @optional ]]; then
		optional=true
		shift
	fi

	OPT=$1 OPTARG= OPTSHIFT=0

	if [[ $1 == -[!-]?* ]]; then
		OPT=${1:0:2} OPTARG=${1:2}
	elif [[ $1 == --*=* ]]; then
		OPT=${1%%=*} OPTARG=${1#*=}
	elif [[ ${2+.} && (${optional} == false || $2 != -?*) ]]; then
		OPTARG=$2 OPTSHIFT=1
	elif [[ ${optional} == true ]]; then
		return 1
	else
		fail "No argument specified for '$1'."
	fi

	return 0
}

function process_opt_with_arg {
	local checker=$1 arg_is_list=$2
	get_opt_and_optarg "${@:3}"
	[[ ${arg_is_list} == true ]] && OPTARG=${OPTARG//+(,)/,} OPTARG=${OPTARG#,} OPTARG=${OPTARG%,}
	"${checker}" "${OPT}" "${OPTARG}"
	__I0=$(( OPTSHIFT + 1 ))
	HAS_ARG=true
}

function parse_filter_opts {
	local id=$1 HAS_ARG=false
	shift

	case $1 in
	-e*|--euid?(=*))
		process_opt_with_arg check_if_valid_name_or_id_list_arg true "$@"
		FILTER_EUIDS[id]+=,${OPTARG}
		;;
	-g*|--group?(=*))
		process_opt_with_arg check_if_valid_name_or_id_list_arg true "$@"
		FILTER_GROUPS[id]+=,${OPTARG}
		;;
	-i|--ignore-case)
		FILTER_IGNORE_CASE[id]=true
		__I0=1
		;;
	-I|--no-ignore-case)
		FILTER_IGNORE_CASE[id]=false
		__I0=1
		;;
	-n*|--ns?(=*))
		process_opt_with_arg check_if_valid_pid_arg false "$@"
		FILTER_NS[id]=${OPTARG}
		;;
	-N*|--nslist?(=*))
		process_opt_with_arg check_if_valid_nslist_arg true "$@"
		FILTER_NSLIST[id]+=,${OPTARG}
		;;
	-p*|--pgroup?(=*))
		process_opt_with_arg check_if_valid_id_list_arg true "$@"
		FILTER_PGROUPS[id]+=,${OPTARG}
		;;
	-T*|--terminal?(=*))
		process_opt_with_arg check_if_not_empty_arg true "$@"
		FILTER_TERMINAL[id]+=,${OPTARG}
		;;
	-u*|--uid?(=*))
		process_opt_with_arg check_if_valid_name_or_id_list_arg true "$@"
		FILTER_UIDS[id]+=,${OPTARG}
		;;
	-x|--exact)
		FILTER_EXACT[id]=true
		__I0=1
		;;
	-X|--no-exact)
		FILTER_EXACT[id]=false
		__I0=1
		;;
	-z*|--session?(=*))
		process_opt_with_arg check_if_valid_id_list_arg true "$@"
		FILTER_SESSION[id]+=,${OPTARG}
		;;
	-[!-][!-]*)
		parse_filter_opts "${id}" "-${1:0:2}" && parse_filter_opts "${id}" "-${1:2}" "${@:2}"
		return
		;;
	*)
		__I0=0
		return 1
		;;
	esac

	[[ ${HAS_ARG} == true && SEC_GLOBAL_ID -eq 0 ]] && HAS_GEN_FILTERS[id]=true
	return 0
}

function parse_target_expr {
	local target opts

	if [[ ${1//[!/]} == *//* ]]; then
		fail "Unexpected use of too many '/' in argument: $1"
	elif [[ $1 == */* ]]; then
		target=${1%%/*} opts=${1#*/}
	else
		target=$1 opts=
	fi

	(( ++TARGET_ID ))
	[[ ${target} ]] && TARGETS[TARGET_ID]=${target}
	set -- ${opts}

	while [[ $# -gt 0 ]]; do
		parse_filter_opts "${TARGET_ID}" "${@:1:2}" || \
			fail "Invalid or unexpected argument in options list of target '${target}': $1"

		shift "$__I0"
	done
}

function get_merged_list {
	local var=$1 a i r temp= IFS=,
	shift

	for i; do
		r=${var}[$i]
		temp+=,${!r}
	done

	__=

	for a in ${temp#,}; do
		[[ $a && ,$__, != *,"$a",* ]] && __+=,$a
	done

	__=${__#,}
	[[ $__ ]]
}

function is_effectively_true {
	local effective __

	for __; do
		[[ $__ ]] && effective=$__
	done

	[[ ${effective} == true ]]
}

function get_pgrep_opts {
	local id=$1 gid=0
	__A0=()

	if [[ ${2-} == @sec ]]; then
		[[ LAST_SEC_TARGET_ID -gt 0 ]] && return 1
		gid=${SEC_GLOBAL_ID}
	elif [[ ${2-} == @ter ]]; then
		[[ LAST_TER_TARGET_ID -gt 0 ]] && return 1
		gid=${TER_GLOBAL_ID}
	fi

	if [[ id -eq gid ]]; then
		set -- "${id}"
		is_effectively_true "${FILTER_EXACT_DEFAULT}" "${FILTER_EXACT_SUPER}" \
				"${FILTER_EXACT[id]-}" && __A0+=(--exact)
		is_effectively_true "${FILTER_IGNORE_CASE_DEFAULT}" "${FILTER_IGNORE_CASE_SUPER}" \
				"${FILTER_IGNORE_CASE[id]-}" && __A0+=(--ignore-case)
	else
		set -- "${gid}" "${id}"
		is_effectively_true "${FILTER_EXACT_DEFAULT}" "${FILTER_EXACT_SUPER}" \
				"${FILTER_EXACT[gid]-}" "${FILTER_EXACT[id]-}" && __A0+=(--exact)
		is_effectively_true "${FILTER_IGNORE_CASE_DEFAULT}" "${FILTER_IGNORE_CASE_SUPER}" \
				"${FILTER_IGNORE_CASE[gid]-}" "${FILTER_IGNORE_CASE[id]-}" && __A0+=(--ignore-case)
	fi

	get_merged_list FILTER_EUIDS "$@" && __A0+=(--euid="$__")
	get_merged_list FILTER_GROUPS "$@" && __A0+=(--group="$__")
	get_merged_list FILTER_NSLIST "$@"&& __A0+=(--nslist="$__")
	get_merged_list FILTER_NS "$@" && __A0+=(--ns="$__")
	get_merged_list FILTER_PGROUPS "$@" && __A0+=(--pgroup="$__")
	get_merged_list FILTER_SESSION "$@" && __A0+=(--session="$__")
	get_merged_list FILTER_TERMINAL "$@" && __A0+=(--terminal="$__")
	get_merged_list FILTER_UIDS "$@" && __A0+=(--uid="$__")
	[[ ${#__A0[@]} -gt 0 ]]
}

function collect_initial_targets {
	local id pgrep_opts=() phrase pids target target_pids=() reg=() pid

	for (( id = 0; id <= LAST_PRI_TARGET_ID; ++id )); do
		[[ ${TARGETS[id]+.} ]] && target=${TARGETS[id]} || target=()
		get_pgrep_opts "${id}"
		pgrep_opts=("${__A0[@]}")

		if [[ ${target-} == +([[:digit:]]) ]]; then
			if [[ ${target} == "${SELF}" ]]; then
				warn_excluding_self
			elif [[ ${pgrep_opts+.} ]]; then
				for pid in $(pgrep "${pgrep_opts[@]}"); do
					if [[ ${target} == "${pid}" ]]; then
						target_pids+=("${target}")
						break
					fi
				done
			else
				target_pids+=("${target}")
			fi
		elif [[ ${target+.} || (${pgrep_opts+.} && (id -gt 0 || LAST_PRI_TARGET_ID -eq 0)) ]]; then
			pids=($(pgrep "${pgrep_opts[@]}" -- "${target[@]}"))
			exclude_self "${pids[@]}"

			if [[ (${#__A0[@]} -eq 0 && ${quiet} == false) || ${VERBOSE} == true ]]; then
				if [[ ${target+.} && ${pgrep_opts+.} ]]; then
					phrase="pattern '${target}' and pgrep options '${pgrep_opts[*]}'"
				elif [[ ${target} ]]; then
					phrase="pattern '${target}'"
				else
					phrase="pgrep option(s) '${pgrep_opts[*]}'"
				fi
			fi

			if [[ ${#__A0[@]} -eq 0 ]]; then
				log_info "No targets matched using ${phrase}."
			else
				[[ ${VERBOSE} == true ]] && log_verbose "Targets matching ${phrase}: ${__A0[*]}"
				target_pids+=("${__A0[@]}")
			fi
		fi
	done

	if [[ ${#target_pids[@]} -eq 0 ]]; then
		log_info 'No targets matched expressions.'
		return 1
	fi

	for id in "${target_pids[@]}"; do
		if [[ -z ${reg[id]} ]]; then
			INITIAL_TARGET_PIDS+=("${id}")
			reg[id]=.
		fi
	done

	return 0
}

function prepare_secondary_filter {
	if [[ SEC_GLOBAL_ID -gt 0 ]]; then
		local id pgrep_opts=() target args index

		for (( id = SEC_GLOBAL_ID; id <= LAST_SEC_TARGET_ID; ++id )); do
			target=()
			[[ ${TARGETS[id]+.} ]] && target[0]=${TARGETS[id]}
			get_pgrep_opts "${id}" @sec
			pgrep_opts=("${__A0[@]}")

			if [[ ${target-} == +([[:digit:]]) ]]; then
				if [[ ${target} == "${SELF}" ]]; then
					warn_excluding_self
				else
					args=("${pgrep_opts[@]}")
					SEC_FILTER_INDICES[SEC_FILTER_ID]=${#SEC_FILTER_ARGS[@]}
					SEC_FILTER_LENGTHS[SEC_FILTER_ID]=${#args[@]}
					SEC_FILTER_PIDS[SEC_FILTER_ID++]=${target}
					SEC_FILTER_ARGS+=("${args[@]}")
				fi
			elif [[ ${target+.} || (${pgrep_opts+.} && (id -gt SEC_GLOBAL_ID || \
					LAST_SEC_TARGET_ID -eq 0)) ]]; then
				args=("${pgrep_opts[@]}")
				[[ ${target+.} ]] && args+=(-- "${target[@]}")
				SEC_FILTER_INDICES[SEC_FILTER_ID]=${#SEC_FILTER_ARGS[@]}
				SEC_FILTER_LENGTHS[SEC_FILTER_ID++]=${#args[@]}
				SEC_FILTER_ARGS+=("${args[@]}")
			fi
		done

		if [[ ${#SEC_FILTER_INDICES[@]} -eq 1 ]]; then
			function list_children {
				CHILDREN=($(pgrep -P "$1"))
			}
		elif [[ ${#SEC_FILTER_INDICES[@]} -gt 1 ]]; then
			function do_secondary_filter {
				__A0=()

				if [[ $# -gt 0 ]]; then
					local pids=() args pid i

					for i in "${!SEC_FILTER_INDICES[@]}"; do
						args=("${SEC_FILTER_ARGS[@]:${SEC_FILTER_INDICES[i]}:${SEC_FILTER_LENGTHS[i]}}")
						pid=${SEC_FILTER_PIDS[i]-}

						if [[ ${args+.} ]]; then
							for i in $(pgrep "${args[@]}"); do
								[[ -z ${pid} || ${pid} == "$i" ]] && pids[i]=.
							done
						elif [[ ${pid} ]]; then
							pids[pid]=.
						fi
					done

					for i; do
						[[ ${pids[i]+.} ]] && __A0+=("$i")
					done
				fi
			}

			function list_children {
				do_secondary_filter $(pgrep -P "$1")
				CHILDREN=("${__A0[@]}")
			}
		fi
	fi
}

function prepare_tertiary_filter {
	if [[ TER_GLOBAL_ID -gt 0 ]]; then
		local id pgrep_opts=() target args

		for (( id = TER_GLOBAL_ID; id <= LAST_TER_TARGET_ID; ++id )); do
			target=()
			[[ ${TARGETS[id]+.} ]] && target[0]=${TARGETS[id]}
			get_pgrep_opts "${id}" @ter
			pgrep_opts=("${__A0[@]}")

			if [[ ${target-} == +([[:digit:]]) ]]; then
				if [[ ${target-} == "${SELF}" ]]; then
					warn_excluding_self
				else
					args=("${pgrep_opts[@]}")
					TER_FILTER_INDICES[TER_FILTER_ID]=${#TER_FILTER_ARGS[@]}
					TER_FILTER_LENGTHS[TER_FILTER_ID]=${#args[@]}
					TER_FILTER_PIDS[TER_FILTER_ID++]=${target}
					TER_FILTER_ARGS+=("${args[@]}")
				fi
			elif [[ ${target+.} || (${pgrep_opts+.} && (id -gt TER_GLOBAL_ID || \
					LAST_TER_TARGET_ID -eq 0)) ]]; then
				args=("${pgrep_opts[@]}")
				[[ ${target+.} ]] && args+=(-- "${target[@]}")
				TER_FILTER_INDICES[TER_FILTER_ID]=${#TER_FILTER_ARGS[@]}
				TER_FILTER_LENGTHS[TER_FILTER_ID++]=${#args[@]}
				TER_FILTER_ARGS+=("${args[@]}")
			fi
		done
	fi

	if [[ ${#TER_FILTER_INDICES[@]} -gt 0 ]]; then
		function do_tertiary_filter {
			__A0=()

			if [[ $# -gt 0 ]]; then
				local pids=() args pid i

				for i in "${!TER_FILTER_INDICES[@]}"; do
					args=("${TER_FILTER_ARGS[@]:${TER_FILTER_INDICES[i]}:${TER_FILTER_LENGTHS[i]}}")
					pid=${TER_FILTER_PIDS[i]-}

					if [[ ${args+.} ]]; then
						for i in $(pgrep "${args[@]}"); do
							[[ -z ${pid} || ${pid} == "$i" ]] && pids[i]=.
						done
					elif [[ ${pid} ]]; then
						pids[pid]=.
					fi
				done

				for i; do
					[[ ${pids[i]+.} ]] && __A0+=("$i")
				done
			fi
		}
	else
		function do_tertiary_filter {
			__A0=("$@")
		}
	fi
}	

function get_process_cmd {
	CMD=

	if [[ ${VERBOSE} == true && -r /proc/$1/cmdline ]]; then
		local REPLY

		while read -rd ''; do
			CMD+="${REPLY} "
		done < "/proc/$1/cmdline"

		CMD=${CMD% }
	elif [[ -r /proc/$1/comm ]]; then
		IFS= read -r CMD < "/proc/$1/comm"
	fi
}

function ask_for_yn {
	for (( ;; )); do
		IFS= read -n1 -d '' -p "$1"
		[[ ${REPLY} != $'\n' ]] && echo

		case ${REPLY} in
		[yY])
			return 0
			;;
		[nN])
			return 1
			;;
		esac

		echo "Please say Y or N."
	done
}

function ask_send_sig {
	local signal=$1 CMD; shift

	if [[ $# -eq 0 ]]; then
		return 1
	elif [[ $# -eq 1 ]]; then
		get_process_cmd "$1"
		ask_for_yn "Send ${signal} to $1${CMD:+" (${CMD})"}? "
	else
		local i=0 l __

		for __; do
			i=${#__}
			[[ i -gt l ]] && l=$i
		done

		echo "Send ${signal} to these processes? " >&2
		printf '%*s %s\n' "$l" PID CMD >&2

		for __; do
			get_process_cmd "$__"
			printf '%*s %s\n' "$l" "$__" "${CMD}" >&2
		done

		ask_for_yn "> "
	fi
}

function setup_kill_function {
	if [[ ${VERBOSE} == true ]]; then
		if [[ ${ASK} == true ]]; then
			function kill {
				local __
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"

				for __ in "${__A0[@]}"; do
					ask_send_sig "$2" "$__" || continue
					log_verbose "Sending $2 to:" "$__"
					[[ ${PRETEND} != true ]] && builtin kill -s "$2" "$__"
				done
			}
		elif [[ ${ASK_ONCE} == true ]]; then
			function kill {
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"

				if [[ ${#__A0[@]} -gt 0 ]] && ask_send_sig "$2" "${__A0[@]}"; then
					log_verbose "Sending $2 to:" "${__A0[@]}"
					[[ ${PRETEND} != true ]] && builtin kill -s "$2" "${__A0[@]}"
				fi
			}
		else
			function kill {
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"

				if [[ ${#__A0[@]} -gt 0 ]]; then
					log_verbose "Sending $2 to:" "${__A0[@]}"
					[[ ${PRETEND} != true ]] && builtin kill -s "$2" "${__A0[@]}"
				fi
			}
		fi
	else
		if [[ ${ASK} == true ]]; then
			function kill {
				local __
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"

				for __ in "${__A0[@]}"; do
					ask_send_sig "$2" "$__" && [[ ${PRETEND} != true ]] && \
						builtin kill -s "$2" "$__"
				done
			}
		elif [[ ${ASK_ONCE} == true ]]; then
			function kill {
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"
				[[ ${#__A0[@]} -gt 0 ]] && ask_send_sig "$2" "${__A0[@]}" && \
						[[ ${PRETEND} != true ]] && builtin kill -s "$2" "${__A0[@]}"
			}
		else
			function kill {
				exclude_self "${@:3}"
				do_tertiary_filter "${__A0[@]}"
				[[ ${#__A0[@]} -gt 0 && ${PRETEND} != true ]] && builtin kill -s "$2" "${__A0[@]}"
			}
		fi
	fi
}

function parse_tertiary_args {
	TER_GLOBAL_ID=$(( ++TARGET_ID ))

	while [[ $# -gt 0 ]]; do
		if parse_filter_opts "${TER_GLOBAL_ID}" "${@:1:2}"; then
			shift "$__I0"
		else
			case $1 in
			--)
				while shift; [[ ${1+.} ]]; do
					[[ $1 == // ]] && fail "Unexpected third use of '//'."
					parse_target_expr "$1"
					LAST_TER_TARGET_ID=${TARGET_ID}
				done
				;;
			-*)
				fail "Invalid or unexpected option '$1'."
				;;
			//)
				fail "Unexpected third use of '//'."
				;;
			+(/))
				fail "Invalid argument: $1"
				;;
			*)
				parse_target_expr "$1"
				LAST_TER_TARGET_ID=${TARGET_ID}
				;;
			esac

			shift
		fi
	done
}

function parse_secondary_args {
	SEC_GLOBAL_ID=$(( ++TARGET_ID ))

	while [[ $# -gt 0 ]]; do
		if [[ $1 == // ]]; then
			parse_tertiary_args "${@:2}"
			break
		elif parse_filter_opts "${SEC_GLOBAL_ID}" "${@:1:2}"; then
			shift "$__I0"
		else
			case $1 in
			--)
				while shift; [[ ${1+.} ]]; do
					[[ $1 == // ]] && continue 2
					parse_target_expr "$1"
					LAST_SEC_TARGET_ID=${TARGET_ID}
				done
				;;
			-*)
				fail "Invalid or unexpected option '$1'."
				;;
			+(/))
				fail "Invalid argument: $1"
				;;
			*)
				parse_target_expr "$1"
				LAST_SEC_TARGET_ID=${TARGET_ID}
				;;
			esac

			shift
		fi
	done
}

function main {
	local function_suffix= ignore_sighup=false list_ref=TREE[@] quiet=false signal=SIGTERM \
			strategy=simultaneous target_class=tree __

	while [[ $# -gt 0 ]]; do
		if [[ $1 == // ]]; then
			parse_secondary_args "${@:2}"
			break
		elif parse_filter_opts 0 "${@:1:2}"; then
			shift "$__I0"
		else
			case $1 in
			-a|--ask)
				ASK=true
				;;
			-A|--ask-once)
				ASK_ONCE=true
				;;
			-c|--children|--children-only)
				list_ref=CHILDREN[@]
				target_class=children
				;;
			-d|--descendants|--descendants-only)
				list_ref=DESCENDANTS[@]
				target_class=descendants
				;;
			-Gi|--global-ignore-case)
				FILTER_IGNORE_CASE_SUPER=true
				;;
			-GI|--global-no-ignore-case)
				FILTER_IGNORE_CASE_SUPER=false
				;;
			-Gx|--global-exact)
				FILTER_EXACT_SUPER=true
				;;
			-GX|--global-no-exact)
				FILTER_EXACT_SUPER=false
				;;
			-h|--help)
				show_help_info
				return 1
				;;
			-H|--ignore-sighup)
				ignore_sighup=true
				;;
			-o|--one-at-a-time)
				strategy=one-at-a-time
				function_suffix='_2'
				;;
			-P|--pretend)
				PRETEND=true
				;;
			-q|--quiet)
				quiet=true
				VERBOSE=false
				;;
			-r|--reverse)
				strategy=reverse
				function_suffix='_3'
				;;
			-s*|--signal?(=*))
				get_opt_and_optarg "$@"
				signal=${OPTARG}
				shift "${OPTSHIFT}"
				;;
			-S|--simultaneous)
				strategy=simultaneous
				function_suffix=
				;;
			-t|--tree)
				list_ref=TREE[@]
				target_class=tree
				;;
			-U|--unify)
				strategy=unify
				;;
			-v|--verbose)
				quiet=false
				VERBOSE=true
				;;
			-V|--version)
				echo "${VERSION}"
				return 2
				;;
			--)
				while shift; [[ ${1+.} ]]; do
					[[ $1 == // ]] && continue 2
					parse_target_expr "$1"
					LAST_PRI_TARGET_ID=${TARGET_ID}
				done
				;;
			-+([[:digit:]]))
				signal=${1#-}
				;;
			-[!-][!-]*)
				set -- "${1:0:2}" "-${1:2}" "${@:2}"
				;;
			-?*)
				fail "Invalid option: $1"
				;;
			+(/))
				fail "Invalid argument: $1"
				;;
			*)
				parse_target_expr "$1"
				LAST_PRI_TARGET_ID=${TARGET_ID}
				;;
			esac

			shift
		fi
	done

	if [[ ${ASK_ONCE} == true ]]; then
		[[ ${ASK} != true ]] || \
			fail "Options '--ask' and '--ask-once' can't be used at the same time."
		[[ ${strategy} == @(simultaneous|unify) ]] || \
			fail "Option '--ask-once' can only be used in 'simultaneous' or 'unify' strategy mode."
	fi

	if [[ (${ASK} == true || ${ASK_ONCE} == true) && ! -d /proc/$$ ]]; then
		if type -P uname >/dev/null && [[ $(uname -r) == Linux ]]; then
			log_warning "Procfs (/proc) is needed to resolve PIDs to command names."
		fi
	fi

	[[ LAST_PRI_TARGET_ID -gt 0 || ${#HAS_GEN_FILTERS[@]} -gt 0 ]] ||  \
		fail "No target or target-generating filters specified.  Run with '--help' for usage info."

	[[ ${VERBOSE} == true ]] || function log_verbose { :; }

	if [[ ${quiet} == true ]]; then
		function log_info { :; }
		function log_warning { :; }
	fi

	[[ ${ignore_sighup} == true ]] && trap : SIGHUP
	collect_initial_targets || return 1
	log_verbose "Initial targets: ${INITIAL_TARGET_PIDS[@]}"
	log_verbose "Self: ${SELF}"
	prepare_secondary_filter
	prepare_tertiary_filter
	setup_kill_function

	if [[ ${strategy} == unify ]]; then
		local func=list_${target_class} list=() reg=() i=0

		for __ in "${INITIAL_TARGET_PIDS[@]}"; do
			log_verbose "Call: ${func} $__"
			"${func}" "$__" "${signal}"

			for __ in "${!list_ref}"; do
				if [[ -z ${reg[$__]} ]]; then
					list[i++]=$__
					reg[$__]=.
				fi
			done
		done

		kill "${list[@]}"
	else
		local func=kill_${target_class}
		[[ ${target_class} != children ]] && func+=${function_suffix}

		for __ in "${INITIAL_TARGET_PIDS[@]}"; do
			log_verbose "Call: ${func} $__"
			"${func}" "$__" "${signal}"
		done
	fi

	log_verbose Done.
	return 0
}

main "$@"
