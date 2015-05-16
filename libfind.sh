#!/bin/bash

# ----------------------------------------------------------------------

# libfind.sh
#
# Finds library files based on expressions.
#
# By default it searches for files in directories specified in
# /etc/ld.so.conf but it can be configured to use other directories
# instead.
#
# Usage: libfind[.sh] [options] [-e] expression [[--] expression ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 13, 2015

# ----------------------------------------------------------------------

VERSION='2015-05-13'

[[ ${BASH_VERSINFO} -ge 4 ]] || {
	echo "This script requires Bash version 4.0 or newer." >&2
	exit 1
}

shopt -s extglob

declare -a LIB_PATHS=()
declare -A LD_CONF_FLAGS=()
declare -a COMMON_LIB_PATHS=(
	/usr/x86_64-pc-linux-gnu/lib64
	/usr/x86_64-pc-linux-gnu/lib32
	/usr/x86_64-pc-linux-gnu/libx32
	/usr/x86_64-pc-linux-gnu/lib
	/usr/i386-pc-linux-gnu/lib32
	/usr/i386-pc-linux-gnu/lib
	/usr/local/lib64
	/usr/local/lib32
	/usr/local/libx32
	/usr/local/lib
	/lib64
	/lib32
	/libx32
	/lib
	/usr/lib64
	/usr/lib32
	/usr/libx32
	/usr/lib
)

function show_help_info {
	echo "Finds library files based on expressions.

By default it searches for files in directories specified in
/etc/ld.so.conf but it can be configured to use other directories
instead.

Usage: $0 [options] [-e] expression [[--] expression ...]

Use of common paths:
  -c               Search in common library directories instead of those
                   specified in /etc/ld.so.conf.
  -C               Same as -c but adds the common library directories
                   into the list derived from /etc/ld.so.conf.

Expression Types:
      --awk        Treat all expressions as Awk regular expressions.
      --egrep      Treat all expressions as egrep expressions.
      --emacs      Treat all expressions as Emacs regular expressions.
  -E, --extended   Treat all expressions as extended regular expressions.
  -r, --regex      Treat all expressions as basic regular expressions.
  -x, --exact      Treat all expressions as exact glob patterns.  No
                   extra wildcard character is added before and after
                   the keyword.
  -s               Treat all expressions as case sensitive.  This option
                   can co-exist with other expression type options.

Others:
  -e               Imply that the following argument is an expression.
  -h, --help       Show this help info.
  -v, --verbose    Be verbose.  (Doesn't really do anything yet.)
  -V, --version    Show version.

Only one of -E, -r and -x can become effective and it would affect all
expressions including the ones specified before them.

Regex-based expression types rely on find's -regex so they would match a
whole pathname and not just a file's filename.

When no expression type is specified, it defaults to glob patterns." >&2
}

function get_clean_path {
	local T1 T2=() I=0 IFS=/

	if [[ $1 == /* ]]; then
		read -ra T1 <<< "$1"
	else
		read -ra T1 <<< "${PWD}/$1"
	fi

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -gt 0 ]] && unset 'T2[--I]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		T2[I++]=$__
	done

	__="/${T2[*]}"
}

function get_lib_paths {
	[[ -z ${LD_CONF_FLAGS[$1]} && -f $1 && -r $1 ]] || return

	LD_CONF_FLAGS[$1]=.

	while read __; do
		case $__ in
		/*)
			get_clean_path "$__"
			LIB_PATHS+=("$__")
			;;
		include\ *)
			local PATTERN=${__##include+([[:blank:]])}

			if [[ -n ${PATTERN} ]]; then
				if [[ ${PATTERN} == /* ]]; then
					get_clean_path "${PATTERN}"
				else
					get_clean_path "$1/../${PATTERN}"
				fi

				while read __; do
					get_lib_paths "$__"
				done < <(compgen -G "$__")
			fi
			;;
		esac
	done < "$1"
}

function fail {
	printf '%s\n' "$1" >&2
	exit 1
}

function main {
	local CASE_SENSITIVE=false EXPRESSIONS=() MODE=default USE_OR_ADD_COMMON_PATHS=false __

	while [[ $# -gt 0 ]]; do
		case $1 in
		-c)
			[[ ${USE_OR_ADD_COMMON_PATHS} == add ]] && fail "You can only specify one of -c and -C."
			USE_OR_ADD_COMMON_PATHS=use
			;;
		-C)
			[[ ${USE_OR_ADD_COMMON_PATHS} == use ]] && fail "You can only specify one of -c and -C."
			USE_OR_ADD_COMMON_PATHS=add
			;;
		--awk|--egrep|--emacs)
			MODE=${1#--}
			;;
		-E|--extended)
			MODE=extended
			;;
		-r|--regex)
			MODE=basic
			;;
		-x|--exact)
			MODE=exact_pattern
			;;
		-s)
			CASE_SENSITIVE=true
			;;
		-e)
			shift
			[[ $# -eq 0 ]] && error "No argument follows -e."
			EXPRESSIONS+=("$1")
			;;
		-h|--help)
			show_help_info
			exit 1
			;;
		-v|--verbose)
			VERBOSE=true
			;;
		-V|--version)
			echo "${VERSION}" >&2
			exit 1
			;;
		--)
			EXPRESSIONS=("${EXPRESSIONS[@]}" "${@:2}")
			break
			;;
		-*)
			fail "Invalid option: $1"
			;;
		*)
			EXPRESSIONS+=("$1")
			;;
		esac

		shift
	done

	[[ ${#EXPRESSIONS[@]} -eq 0 ]] && fail "No expression was specified."

	if [[ ${USE_OR_ADD_COMMON_PATHS} == use ]]; then
		LIB_PATHS=("${COMMON_LIB_PATHS[@]}")
	else
		get_lib_paths /etc/ld.so.conf

		if [[ ${USE_OR_ADD_COMMON_PATHS} == add ]]; then
			LIB_PATHS+=("${COMMON_LIB_PATHS[@]}")
		fi
	fi

	local T=("${!LIB_PATHS[@]}") I=0 J C=${#T[@]} D=0

	for (( ; I < C; ++I )); do
		for (( J = I + 1; J < C; ++J )); do
			[[ ${LIB_PATHS[${T[I]}]} == "${LIB_PATHS[${T[J]}]}" ]] && {
				unset "LIB_PATHS[${T[J]}]" 'T[J]'
				(( ++D ))
			}
		done

		[[ D -gt 0 ]] && {
			T=("${T[@]:I + 1}")
			(( C -= D + I + 1, I = -1, D = 0 ))
		}
	done

	for I in "${!LIB_PATHS[@]}"; do
		__=${LIB_PATHS[I]}
		[[ $__ == *([[:blank:]]) || ! -d $__ || ! -r $__ || ! -x $__ ]] && unset "LIB_PATHS[$I]"
	done

	[[ ${#LIB_PATHS[@]} -eq 0 ]] && return 1

	local NAME_OPT='-iname' REGEX_OPT='-iregex'

	if [[ ${CASE_SENSITIVE} == true ]]; then
		NAME_OPT='-name'
		REGEX_OPT='-regex'
	fi

	local EXPR_OPT=${NAME_OPT} REGEX_TYPE_ARGS=() ADD_WILDCARDS=true

	case ${MODE} in
	awk)
		EXPR_OPT=${REGEX_OPT}
		REGEX_TYPE_ARGS=(-regextype posix-awk)
		ADD_WILDCARDS=false
		;;
	basic)
		EXPR_OPT=${REGEX_OPT}
		REGEX_TYPE_ARGS=(-regextype posix-basic)
		ADD_WILDCARDS=false
		;;
	emacs)
		EXPR_OPT=${REGEX_OPT}
		REGEX_TYPE_ARGS=(-regextype emacs)
		ADD_WILDCARDS=false
		;;
	egrep)
		EXPR_OPT=${REGEX_OPT}
		REGEX_TYPE_ARGS=(-regextype posix-egrep)
		ADD_WILDCARDS=false
		;;
	extended)
		EXPR_OPT=${REGEX_OPT}
		REGEX_TYPE_ARGS=(-regextype posix-extended)
		ADD_WILDCARDS=false
		;;
	exact_pattern)
		EXPR_OPT=${NAME_OPT}
		REGEX_TYPE_ARGS=()
		ADD_WILDCARDS=false
		;;
	esac

	local EXPR_ARGS=()

	if [[ ${ADD_WILDCARDS} == true ]]; then
		for __ in "${EXPRESSIONS[@]}"; do
			EXPR_ARGS+=("${EXPR_OPT}" "*$__*" -and)
		done
	else
		for __ in "${EXPRESSIONS[@]}"; do
			EXPR_ARGS+=("${EXPR_OPT}" "$__" -and)
		done
	fi

	unset "EXPR_ARGS[${#EXPR_ARGS[@]} - 1]"

	find "${LIB_PATHS[@]}" -maxdepth 1 -xtype f "${REGEX_TYPE_ARGS[@]}" "${EXPR_ARGS[@]}"
}

main "$@"
