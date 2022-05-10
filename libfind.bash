#!/bin/bash

# ----------------------------------------------------------------------

# libfind
#
# Finds library files with the use of expressions.
#
# By default, it searches for files in directories specified in
# /etc/ld.so.conf, but it can be configured to use other directories
# instead.
#
# Usage: libfind[.bash] [options] [-e] expression [[--] expression ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 10, 2022

# ----------------------------------------------------------------------

VERSION=2022.05.10

[ -n "${BASH_VERSION}" ] && [[ BASH_VERSINFO -ge 4 ]] || {
	echo "This script requires Bash version 4.0 or newer." >&2
	exit 1
}

set -f +o posix && shopt -s extglob || exit 1

declare -A LD_CONF_HASH=()
declare LIB_PATHS=()
declare LIB_PATHS_COMMON=(/{usr/{x86_64-pc-linux-gnu/,i386-pc-linux-gnu/,local/,},}lib{64,32,x32,})

function show_help_info {
	echo "libfind ${VERSION}

Finds library files based on expressions.

By default it searches for files in directories specified in
/etc/ld.so.conf but it can be configured to use other directories
instead.

Usage: $0 [options] [-e] expression [[--] expression ...]

Use of common paths:
  -c                Search in common library directories instead of
                    those specified in /etc/ld.so.conf.
  -C                Same as -c but adds the common library directories
                    into the list extracted from /etc/ld.so.conf.

Glob-based options:
  -p, --path        Treat all expressions as keywords that will match
                    against the whole path and not just the filename.
  -x, --exact       Treat all expressions as exact glob patterns.  No
                    extra wildcard character is added before or after
                    the keyword.
  -X, --exact-path  Same as -x, but the glob pattern applies with the
                    whole path, and not just the filename.

Regex-based options:
      --awk       Treat all expressions as Awk regular expressions.
      --egrep     Treat all expressions as egrep expressions.
      --emacs     Treat all expressions as Emacs regular expressions.
  -E, --extended  Treat all expressions as extended regular expressions.
  -r, --regex     Treat all expressions as basic regular expressions.

Modifiers:
  -s  Treat all expressions as case sensitive.  This option can co-exist
      with other expression type options.

Others:
  -e EXPR        Treat following argument as an expression.
  -h, --help     Show this help info.
  -V, --version  Show version.

Notes:
  - Only one of --awk, --egrep, --emacs, -E, -r, -p, -x or -X can
    become effective.
  - Regex-based expression types rely on find's -regex so they match a
    whole pathname and not just a file's filename.
  - When no expression type is specified, it defaults to glob patterns."
}

function get_clean_path {
	local t=() i=0 IFS=/

	case $1 in
	/*)
		set -- $1
		;;
	*)
		set -- ${PWD} $1
		;;
	esac

	for __; do
		case $__ in
		..)
			(( i )) && unset 't[--i]'
			continue
			;;
		''|.)
			continue
			;;
		esac

		t[i++]=$__
	done

	__="/${t[*]}"
}

function get_lib_paths {
	# This function tries to comply with ldconfig's behavior.
	# See parse_conf() and parse_conf_include() in ldconfig.c.

	# It expects that IFS is set to default value, and that noglob is set.

	local file=$1

	if [[ -z ${LD_CONF_HASH[${file}]+.} && -f ${file} && -r ${file} ]]; then
		LD_CONF_HASH[${file}]=.

		while read -r __; do
			case $__ in
			/*)
				get_clean_path "$__"
				LIB_PATHS+=("$__")
				;;
			include\ *)
				set -- $__
				shift

				for __; do
					if [[ $__ == /* ]]; then
						get_clean_path "$__"
					else
						get_clean_path "${file}/../$__"
					fi

					while read -r __; do
						get_lib_paths "$__"
					done < <(compgen -G "$__")
				done
				;;
			esac
		done < "${file}"
	fi
}

function fail {
	printf '%s\n' "$@" >&2
	exit 1
}

function get_opt_and_optarg {
	OPT=$1 OPTARG= OPTSHIFT=0

	if [[ $1 == -[!-]?* ]]; then
		OPT=${1:0:2} OPTARG=${1:2}
	elif [[ $1 == --*=* ]]; then
		OPT=${1%%=*} OPTARG=${1#*=}
	elif [[ ${2+.} ]]; then
		OPTARG=$2 OPTSHIFT=1
	else
		return 1
	fi

	return 0
}

function main {
	local case_sensitive=false expressions=() mode=default use_or_add_common_paths=false __

	while [[ $# -gt 0 ]]; do
		case $1 in
		-c)
			[[ ${use_or_add_common_paths} == add ]] && fail "Only one of -c or -C can be specified."
			use_or_add_common_paths=use
			;;
		-C)
			[[ ${use_or_add_common_paths} == use ]] && fail "Only one of -c or -C can be specified."
			use_or_add_common_paths=add
			;;
		--awk|--egrep|--emacs)
			mode=${1#--}
			;;
		-E|--extended)
			mode=extended
			;;
		-p|--path)
			mode=path
			;;
		-r|--regex)
			mode=basic
			;;
		-x|--exact)
			mode=exact_pattern
			;;
		-X)
			mode=exact_path_pattern
			;;
		-s)
			case_sensitive=true
			;;
		-e*)
			get_opt_and_optarg "${@:1:2}" || fail "No argument follows -e."
			expressions+=("${OPTARG}")
			shift "${OPTSHIFT}"
			;;
		-h|--help)
			show_help_info
			return 2
			;;
		-V|--version)
			echo "${VERSION}"
			return 2
			;;
		--)
			expressions+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			fail "Invalid option: $1"
			;;
		*)
			expressions+=("$1")
			;;
		esac

		shift
	done

	[[ ${#expressions[@]} -eq 0 ]] && \
		fail "No expression was specified.  Run with --help to get usage info."

	if [[ ${mode} == @(default|exact_pattern) ]]; then
		for __ in "${expressions[@]}"; do
			if [[ $__ == */* ]]; then
				fail "Forward-slash (/) can't be included when matching against a filename." \
						"Please run libfind with --help to see other search methods."
			fi
		done
	fi

	if [[ ${use_or_add_common_paths} == use ]]; then
		LIB_PATHS=("${LIB_PATHS_COMMON[@]}")
	else
		get_lib_paths /etc/ld.so.conf

		if [[ ${use_or_add_common_paths} == add ]]; then
			LIB_PATHS+=("${LIB_PATHS_COMMON[@]}")
		fi
	fi

	local lib_paths_filtered=()
	local -A reg=()

	for __ in "${LIB_PATHS[@]}"; do
		if [[ $__ != *([[:blank:]]) && -z ${reg[$__]+.} && -d $__ && -r $__ && -x $__ ]]; then
			lib_paths_filtered+=("$__")
			reg[$__]=.
		fi
	done

	[[ ${#lib_paths_filtered[@]} -eq 0 ]] && return 1

	local name_opt="-iname" path_opt="-ipath" regex_opt="-iregex"

	if [[ ${case_sensitive} == true ]]; then
		name_opt="-name"
		regex_opt="-regex"
		path_opt="-path"
	fi

	local expr_opt=${name_opt} regex_type_args=() add_wildcards=true

	case ${mode} in
	awk)
		expr_opt=${regex_opt}
		regex_type_args=(-regextype posix-awk)
		add_wildcards=false
		;;
	basic)
		expr_opt=${regex_opt}
		regex_type_args=(-regextype posix-basic)
		add_wildcards=false
		;;
	emacs)
		expr_opt=${regex_opt}
		regex_type_args=(-regextype emacs)
		add_wildcards=false
		;;
	egrep)
		expr_opt=${regex_opt}
		regex_type_args=(-regextype posix-egrep)
		add_wildcards=false
		;;
	extended)
		expr_opt=${regex_opt}
		regex_type_args=(-regextype posix-extended)
		add_wildcards=false
		;;
	exact_pattern)
		expr_opt=${name_opt}
		regex_type_args=()
		add_wildcards=false
		;;
	exact_path_pattern)
		expr_opt=${path_opt}
		regex_type_args=()
		add_wildcards=false
		;;
	path)
		expr_opt=${path_opt}
		regex_type_args=()
		;;
	esac

	local expr_args=()

	if [[ ${add_wildcards} == true ]]; then
		for __ in "${expressions[@]}"; do
			expr_args+=("${expr_opt}" "*$__*")
		done
	else
		for __ in "${expressions[@]}"; do
			expr_args+=("${expr_opt}" "$__")
		done
	fi

	find "${lib_paths_filtered[@]}" -maxdepth 1 -xtype f "${regex_type_args[@]}" "${expr_args[@]}"
}

main "$@"
