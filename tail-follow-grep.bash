#!/bin/bash

# ----------------------------------------------------------------------

# tail-follow-grep
#
# Basically a wrapper for 'tail -f' and 'grep --line-buffered'
#
# Usage: tailgrep[.bash] [options] -e expr ... [--] file ...
#
# This tool requires GNU versions of tail and grep, any version of cat.
#
# Copyright (c) 2022 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# “Software”), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# ----------------------------------------------------------------------

VERSION=2022.04.29

shopt -s extglob && set +o posix || exit
[[ BASH_VERSINFO -ge 5 ]] && set -u

function fail {
	printf '%s\n' "$1" >&2
	exit "${2-1}"
}

function show_usage {
	echo "Basically a wrapper for 'tail -f' and 'grep --line-buffered'

It runs a pipeline with tail as the first process followed by one or more greps.

Usage: $0 [options] -e expr ... [--] file ...
       $0 -h|--help|-V|--version

Filtering Options:
  -e                           Same as -I
  -I, --include expr [@flags]  Include lines matching expression
  -X, --exclude expr [@flags]  Exclude lines matching expression
  -E, --extended-regexp        Expressions are extended regular
  -F, --fixed-strings          Expressions are literal strings
  -G, --basic-regexp           Expressions are basic regular
  -P, --perl-regexp            Expressions are Perl regular
  -i, --ignore-case            Ignore case
  -l, --line-regexp            Match only whole lines
  -w, --word-regexp            Match only whole words

Tail Options:
  -a, --all-lines              Pass --lines=+1 option to tail
  -c, --bytes +N               Pass --bytes option to tail
  -m, --max-unchanged-stats N  Pass --max-unchanged-stats option to tail
  -n, --lines [+]N             Pass --lines option to tail
  -p, --pid PID                Pass --pid option to tail
  -q, --quiet, --silent        Pass --quiet option to tail
  -R, --follow-name-and-retry  Pass --follow=name and --retry options to tail
  -r, --retry                  Pass --retry option to tail
  -s, --sleep-interval N       Pass --sleep-interval option to tail

Other Options:
  -L, --limit-final [N[,S]|+N]  This enables limiting the final output's initial
                                number of lines displayed to N after S seconds
                                of inactivity.  N defaults to 10 if unspecified.
                                S defaults to 1.  If +N is specified, output
                                starts from N instead.  This option triggers -a
                                behavior as well but -n|--lines can override it.
  -z, --null                    Treat input and produce output as NUL delimited
  -h, --help                    Show this usage info and exit
  -V, --version                 Show version and exit

Notes:
  - All filtering options are processed inclusively using multiple greps.
    To filter out more than one matches, use '|' on an expression with extended
    regex or Perl regex enabled.
  - Expression flags can be 'E', 'F', 'G', 'P', 'l', 'i', or 'w'.
    They allow option behavior to work specifically on the expression." >&2
}

function normalize_args {
	# This function can be improved to allow options to have multiple mandatory
	# arguments by adding another parameter with "opt:n ..." format and making
	# the code treat 2+ arguments as non-opts.

	local with_args=$1 with_optional_args=$2 long_opts_with_args=" $3 " \
			long_opts_with_optional_args=" $4 " __
	shift 4
	ARGS=()

	while [[ $# -gt 0 ]]; do
		case $1 in
		--)
			ARGS+=("$@")
			break
			;;
		--*=*|-)
			ARGS+=("$1")
			;;
		--*)
			if [[ ${2+.} && (${long_opts_with_args} == *" ${1#--} "* || \
					${long_opts_with_optional_args} == *" ${1#--} "* && ($2 == - || \
					$2 != -*)) ]]; then
				ARGS+=("$1=$2")
				shift
			else
				ARGS+=("$1")
			fi
			;;
		-*)
			for (( i = 1; i < ${#1}; ++i )); do
				__=${1:i:1}

				if (( i == ${#1} - 1 )); then
					if [[ ${2+.} && (${with_args} == *"$__"* || ${with_optional_args} == *"$__"* \
							&& ($2 == - || $2 != -*)) ]]; then
						ARGS+=(-"$__=$2")
						shift
						break
					else
						ARGS+=(-"$__")
					fi
				elif [[ ${with_args}${with_optional_args} == *"$__"* ]]; then
					ARGS+=(-"$__=${1:i + 1}")
					break
				else
					ARGS+=(-"$__")
				fi
			done
			;;
		*)
			ARGS+=("$1")
			;;
		esac

		shift
	done
}

function remove_file_if_exists {
	[[ ! -e $1 ]] || rm -- "$1" || {
		echo "Failed to remove '$1'." >&2
		return 1
	}
}

function main {
	local cmds=() complete_cmd expressions=() expr_flags=() expr_opts=() files=() final_limit= \
			flags global_flags=G grep_opts invalid_flags null=false optarg pw= tail_opts=(-f) \
			timeout=1 z_opt=() __

	normalize_args eIXcmnps LW 'bytes max-unchanged-stats lines pid sleep-interval' \
			'limit-final pipe-watch' "$@"
	set -- "${ARGS[@]}"

	while __=${1-}; shift; do
		case $__ in
		-[eIX]?(=*))
			[[ $__ != *=* ]] && fail "No argument specified for '$__'."
			opt=${__%%=*} optarg=${__#*=}
			[[ -z ${optarg} ]] && fail "Argument for '${opt}' can't be empty."
			expressions+=("${optarg}")
			expr_opts+=("${opt}")

			if [[ ${1-} == @* ]]; then
				flags=${1#?} invalid_flags=${flags//[EFGPliw]}
				[[ ${invalid_flags} ]] && fail "Invalid flags specified: ${invalid_flags}"
				expr_flags+=("${flags}")
				shift
			else
				expr_flags+=('')
			fi
			;;
		-E|--extended-regexp)
			global_flags+=E
			;;
		-F|--fixed-strings)
			global_flags+=F
			;;
		-G|--basic-regexp)
			global_flags+=G
			;;
		-P|--perl-regexp)
			global_flags+=P
			;;
		-i|--ignore-case)
			global_flags+=i
			;;
		-l|--line-regexp)
			global_flags+=l
			;;
		-w|--word-regexp)
			global_flags+=w
			;;
		-h|--help|-\?)
			show_usage
			return 2
			;;
		-a|--all-lines)
			tail_opts+=(--lines=+1)
			;;
		@(-c|--bytes|-m|--max-unchanged-stats|-n|--lines|-p|--pid|-s|--sleep-interval)?(=*))
			[[ $__ != *=* ]] && fail "No argument specified for '$__'."
			opt=${__%%=*} optarg=${__#*=}
			[[ -z ${optarg} ]] && fail "Argument for '${opt}' can't be empty."
			[[ ${opt} == -m ]] && opt=--max-unchanged-stats
			[[ ${opt} == -p ]] && opt=--pid
			tail_opts+=("${opt}" "${optarg}")
			;;
		-q|--quiet|--silent|-r|--retry)
			[[ $__ == -r ]] && __=--retry
			tail_opts+=("$__")
			;;
		-R|--follow-name-and-retry)
			tail_opts+=(--follow=name --retry)
			;;
		@(-L|--limit-final)?(=*))
			opt=${__%%=*}
			final_limit=10 timeout=1

			if [[ $__ == *=* ]]; then
				optarg=${__#*=}

				if [[ ${optarg} == *,* ]]; then
					final_limit=${optarg%%,*} timeout=${optarg#*,}
				else
					final_limit=${optarg}
				fi

				[[ ${final_limit} =~ ^\+?[0-9]+$ ]] || \
					fail "Invalid limit value argument for '${opt}': ${final_limit}"
				[[ ${final_limit} =~ ^\+[0-9]+$ && ${optarg} == *,* ]] && \
					fail "No point specifying timeout argument while specifying +N argument to '${opt}': ${optarg}"
				[[ ${timeout} =~ ^[0-9]+$ && timeout -gt 0 ]] || \
					fail "Invalid timeout value argument for '${opt}': ${timeout}"
			fi

			tail_opts+=(--lines=+1)
			;;
		-V|--version)
			echo "${VERSION}"
			return 2
			;;
		-z|--null)
			z_opt=(-z)
			null=true
			;;
		--)
			files+=("$@")
			break
			;;
		-)
			files+=(-)
			;;
		-*)
			fail "Invalid option: ${__%%=*}"
			;;
		*)
			files+=("$__")
			;;
		esac
	done

	[[ ${#files[@]} -gt 0 ]] || fail "No files were specified."
	[[ ${#expressions[@]} -gt 0 ]] || fail "No expressions were specified."
	printf -v 'cmds[0]' '%q ' tail "${z_opt[@]}" "${tail_opts[@]}" -- "${files[@]}"

	for i in "${!expressions[@]}"; do
		flags=${global_flags}${expr_flags[i]}
		grep_opts=${flags//[!EFGP]} grep_opts=${grep_opts:(-1)}
		[[ ${expr_opts[i]} == -X ]] && grep_opts+=v
		[[ ${flags} == *i* ]] && grep_opts+=i
		[[ ${flags} == *w* ]] && grep_opts+=w
		[[ ${flags} == *l* ]] && grep_opts+=x
		[[ ${null} == true ]] && grep_opts+=zZ
		printf -v "cmds[${#cmds[i]}]" '%q ' grep --line-buffered -"${grep_opts}e" \
				"${expressions[i]}"
	done

	printf -v complete_cmd '%s| ' "${cmds[@]}"
	complete_cmd=${complete_cmd%| }
	hash -r tail 2>/dev/null || fail "Tail command not found."
	hash -r grep 2>/dev/null || fail "Grep command not found."

	if [[ ${final_limit} == +* ]]; then
		eval "${complete_cmd} | tail -n ${final_limit} ${z_opt-}"
	elif [[ ${final_limit} ]]; then
		hash -r cat 2>/dev/null || fail "Cat command not found."

		eval "${complete_cmd}" | (
			buffer=() l=0 last_is_partial=false IFS= read_opts=(-rt "${timeout}") format='%s\n'
			[[ ${null} == true ]] && read_opts+=(-d '') format='%s\0'

			while __=; read "${read_opts[@]}" __; do
				buffer[l++ % final_limit]=$__ || exit
			done

			if [[ $? -ne 0 && $__ ]]; then
				buffer[l++ % final_limit]=$__ || exit
				last_is_partial=true
			fi

			for (( i = l > final_limit ? l : 0, j = l > final_limit ? final_limit : l; j > 0;
					++i, --j )); do
				[[ j -eq 1 && ${last_is_partial} == true ]] && format=%s
				printf "${format}" "${buffer[i % final_limit]}" || exit
			done

			exec cat
		)
	else
		eval "${complete_cmd}"
	fi
}

main "$@"
