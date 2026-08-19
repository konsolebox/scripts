#!/bin/bash

# ----------------------------------------------------------

# hist
#
# Shows or modifies Bash's history data
#
# Usage: hist[.bash] [options] [--] [[!]keyword ...]]
#
# Author: konsolebox
# Copyright Free / Public Domain
# Aug. 19, 2026

# ----------------------------------------------------------

_DEFAULT_HISTORY_FILE=~/.bash_history
_NEGATABLE_VARS=negate_final
_VERSION=2026.08.19

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

function die {
	printf '%s\n' "$1"
	exit "${2-1}"
}

function show_usage {
	echo "Shows or modifies Bash's history data

Usage: $0 [options] [--] [[!]keyword ...]]

Options:
  -0, --null                 Use null as the output delimiter
  -b, --bare                 Show plain command output; no dates
  -d, --delete               Delete matched entries from the history file
  -e, -k, --keyword=KEYWORD  Alternative way to specify a keyword
  -E, --edit                 Open history file with an editor
  -f, --file=FILE            Process a different history file
  -i, --ignore-case          Ignore case when matching keywords
  -l, --last                 Only show last match
  -n, --negate               Negate or unnegate results
  -r, --regex                Treat keywords as regex patterns
  -S, --show-location        Show location of the history file
  -u, --unique               Exclude repeated commands in the output
  -w, --match-words          Match keywords against words found in entries
  -Z, --save                 Save results back to the history file
  -h, --help                 Show this usage info and exit
  -V, --version              Show version and exit

Notes:
- All entries are shown if no keywords or mode options are specified.
- Negations take effect before last entry is shown when -l or --last is enabled.

Default history file is '${_DEFAULT_HISTORY_FILE}'."
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
		die "No argument specified for '$1'."
	fi

	return 0
}

function write_info {
	local info=$1 use_null=${2-false} fmt='%s\n'
	[[ ${use_null} == true ]] && fmt='%s\0'
	printf "${fmt}" "${info}"
}

function edit_history_file {
	local file=$1
	[[ ${EDITOR-} ]] || die "EDITOR not specified."
	set -f
	${EDITOR} "${file}"
}

function main {
	local bare_mode=false delete_mode=false edit=false ignore_case=false \
			history_file=${_DEFAULT_HISTORY_FILE} gawk_args=() keywords=() last_only=false \
			negate_final=false regex_mode=false save_mode show_location=false show_version=false \
			unique_mode=false use_null=false var word_mode=false __negatable __

	function get_boolean_option_var {
		case $1 in
		-0|--null)
			__=use_null
			;;
		-b|--bare)
			__=bare_mode
			;;
		-d|--delete)
			__=delete_mode
			;;
		-E|--edit)
			__=edit
			;;
		-i|--ignore-case)
			__=ignore_case
			;;
		-l|--last)
			__=last_only
			;;
		-n|--negate)
			__=negate_final
			__negatable=true
			;;
		-r|--regex)
			__=regex_mode
			;;
		-S|--show-location)
			__=show_location
			;;
		-u|--unique)
			__=unique_mode
			;;
		-V|--version)
			__=show_version
			;;
		-w|--match-words)
			__=word_mode
			;;
		-Z|--save)
			__=save_mode
			;;
		*)
			__=
			return 1
			;;
		esac

		return 0
	}

	while [[ $# -gt 0 ]]; do
		if get_boolean_option_var "$1"; then
			if [[ $__negatable == true && ${!__} == true ]]; then
				eval "$__=false"
			else
				eval "$__=true"
			fi
		else
			case $1 in
			-e*|-k*|--keyword|--keyword=*)
				get_opt_and_optarg "${@:1:2}"
				keywords+=("${OPTARG}")
				shift "${OPTSHIFT}"
				;;
			-f*|--file|--file=*)
				get_opt_and_optarg "${@:1:2}"
				history_file=${OPTARG}
				shift "${OPTSHIFT}"
				;;
			-h|--help)
				show_usage
				return 2
				;;
			--)
				keywords+=("${@:2}")
				break
				;;
			-[!-][!-]*)
				set -- "${1:0:2}" "-${1:2}" "${@:2}"
				continue
				;;
			-?*)
				die "Invalid option: $1" 2
				;;
			*)
				keywords+=("$1")
				;;
			esac
		fi

		shift
	done

	if [[ ${show_version} == true ]]; then
		write_info "${_VERSION}" "${use_null}"
		return 2
	fi

	function check_conflicting_arguments {
		local subject=$1 arg __negatable __
		shift

		for arg; do
			if [[ ${arg} == @keywords ]]; then
				[[ ${keywords+.} ]] && \
					die "Keywords can't be specified along with the '--${subject}' option."
			else
				get_boolean_option_var "--${arg}" || die "Invalid boolean option: ${arg}"
				[[ ${!__} == true ]] && \
					die "Options '--${subject}' and '--${arg}' can't be specified at the same time."
			fi
		done
	}

	if [[ ${show_location} == true ]]; then
		check_conflicting_arguments show-location @keywords bare delete edit ignore-case last \
				match-words negate regex save unique
		write_info "${history_file}" "${use_null}"
		return
	elif [[ ${edit} == true ]]; then
		check_conflicting_arguments edit @keywords bare delete ignore-case last match-words \
				negate null regex save unique
		edit_history_file "${history_file}"
		return
	elif [[ ${negate_final} == true ]]; then
		[[ ${keywords+.} ]] || die "Negate mode requires keywords to be specified."
	fi

	[[ -e ${history_file} ]] || die "History file doesn't exist: ${history_file}"
	[[ -f ${history_file} ]] || die "History file not a file: ${history_file}"
	[[ -r ${history_file} ]] || die "History file not readable: ${history_file}"

	if [[ ${save_mode} == true ]]; then
		check_conflicting_arguments save bare delete last null
		gawk_args=(-i inplace -v save_mode=1)
	elif [[ ${delete_mode} == true ]]; then
		check_conflicting_arguments delete bare last null unique
		[[ ${keywords+.} ]] || die "Delete mode requires keywords to be specified."
		gawk_args=(-i inplace -v delete_mode=1)
	fi

	for var in bare_mode ignore_case last_only negate_final regex_mode unique_mode use_null \
			word_mode; do
		[[ ${!var} == true ]] && gawk_args+=(-v "${var}=1")
	done

	exec gawk "${gawk_args[@]}" '
		BEGIN {
			if (ARGC > 2) {
				for (i = 2; i < ARGC; ++i) {
					negate[i] = ARGV[i] ~ /^!/
					keywords[i] = negate[i] ? substr(ARGV[i], 2) : ARGV[i]
				}

				ARGC = 2
			} else
				show_all = 1

			if (ignore_case && regex_mode)
				IGNORECASE = 1

			if (use_null)
				ORS = "\0"
		}

		function print_cmd(cmd, timestamp) {
			if (delete_mode || !unique_mode || !seen[cmd]++) {
				if (delete_mode || save_mode) {
					if (timestamp)
						printf "%s%s", timestamp, ORS

					printf "%s%s", cmd, ORS
				} else if (bare_mode)
					printf "%s%s", cmd, ORS
				else if (timestamp)
					printf "%5d  [%s] %s%s", ++counter, strftime("%F %T %z", substr(timestamp, 2)),
							cmd, ORS
				else
					printf "%5d  %s%s", ++counter, cmd, ORS
			}
		}

		{
			if (next_timestamp) {
				timestamp = next_timestamp
				next_timestamp = ""
			}

			if (/^#[[:digit:]]+$/) {
				timestamp = $0
				next
			}

			cmd = $0

			if (timestamp) {
				lastRT = RT

				while (getline > 0) {
					if (/^#[[:digit:]]+$/) {
						next_timestamp = $0
						break
					}

					cmd = cmd lastRT $0
					lastRT = RT
				}
			}

			if (save_mode || delete_mode || cmd !~ /^\s*(#|hist\s*)/) {
				if (!show_all) {
					if (word_mode) {
						patsplit(cmd, a, /\w+/)
						delete words

						for (i in a)
							words[ignore_case ? tolower(a[i]) : a[i]] = 1
					}

					for (i in keywords) {
						keyword = keywords[i]

						if (regex_mode) {
							if (word_mode) {
								found = 0

								for (word in words)
									if ((found = word ~ keyword))
										break
							} else
								found = cmd ~ keyword
						} else {
							if (ignore_case)
								keyword = tolower(keyword)

							found = word_mode ? words[keyword] :
									index(ignore_case ? tolower(cmd) : cmd, keyword)
						}

						if (negate[i])
							found = !found
						if (negate_final)
							found = !found
						if (delete_mode)
							found = !found
						if (!found)
							next
					}
				}

				if (last_only) {
					last_cmd = cmd
					last_timestamp = timestamp
				} else
					print_cmd(cmd, timestamp)
			}
		}

		END {
			if (last_only && length(last_cmd))
				print_cmd(last_cmd, last_timestamp)
		}
	' "${history_file}" "${keywords[@]}"
}

main "$@"
