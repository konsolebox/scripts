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

VERSION=2022.05.05

shopt -s extglob && set +o posix || exit

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
    They allow option behavior to work specifically on the expression."
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

	while [[ $# -gt 0 ]]; do
		case $1 in
		-[eIX]*)
			get_opt_and_optarg "${@:1:2}"
			shift "${OPTSHIFT}"
			[[ ${OPTARG} ]] || fail "Argument for '${OPT}' can't be empty."
			expressions+=("${OPTARG}")
			expr_opts+=("${OPT}")

			if [[ ${2-} == @* ]]; then
				flags=${2#?} invalid_flags=${flags//[EFGPliw]}
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
		-[cmnps]*|--@(bytes|max-unchanged-stats|lines|pid|sleep-interval)?(=*))
			get_opt_and_optarg "${@:1:2}"
			shift "${OPTSHIFT}"
			[[ ${OPTARG} ]] || fail "Argument for '${OPT}' can't be empty."
			[[ ${OPT} == -m ]] && OPT=--max-unchanged-stats
			[[ ${OPT} == -p ]] && OPT=--pid
			tail_opts+=("${OPT}" "${OPTARG}")
			;;
		-q|--quiet|--silent|-r|--retry)
			[[ $__ == -r ]] && __=--retry
			tail_opts+=("$__")
			;;
		-R|--follow-name-and-retry)
			tail_opts+=(--follow=name --retry)
			;;
		-L*|--limit-final?(=*))
			final_limit=10 timeout=1

			if get_opt_and_optarg @optional "${@:1:2}"; then
				shift "${OPTSHIFT}"

				if [[ ${OPTARG} == *,* ]]; then
					final_limit=${OPTARG%%,*} timeout=${OPTARG#*,}
				else
					final_limit=${OPTARG}
				fi

				[[ ${final_limit} =~ ^\+?[0-9]+$ ]] || \
					fail "Invalid limit value argument for '${OPT}': ${final_limit}"
				[[ ${final_limit} =~ ^\+[0-9]+$ && ${OPTARG} == *,* ]] && \
					fail "No point specifying timeout argument while specifying +N argument to '${OPT}': ${OPTARG}"
				[[ ${timeout} =~ ^[0-9]+$ && timeout -gt 0 ]] || \
					fail "Invalid timeout value argument for '${OPT}': ${timeout}"
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
			files+=("${@:2}")
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
			files+=("$1")
			;;
		esac

		shift
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
