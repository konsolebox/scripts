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
# March 6, 2025

# ----------------------------------------------------------

_DEFAULT_HISTORY_FILE=~/.bash_history
_VERSION=2025.03.06

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

function die {
	printf '%s\n' "$1"
	exit "${2-1}"
}

function show_usage_and_exit {
	echo "Shows or modifies Bash's history data

Usage: $0 [options] [--] [[!]keyword ...]]

Options:
  -d, --delete               Delete matched entries from the history file
  -e, -k, --keyword=KEYWORD  Alternative way to specify a keyword
  -f, --file=FILE            Process a different history file
  -E, --edit                 Open history file with an editor
  -h, --help                 Show this usage info and exit
  -i, --ignore-case          Ignore case when mmatching keywords
  -r, --regex                Treat keywords as regex patterns
  -S, --show-location        Show location of the history file
  -w, --match-words          Match keywords against words found in entries
  -V, --version              Show version and exit

All entries are shown if no keywords or mode options are specified.

Default history file is '${_DEFAULT_HISTORY_FILE}'."
	exit 2
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

function edit_history_file_and_exit {
	local file=$1
	[[ ${EDITOR-} ]] || die "EDITOR not specified."
	set -f
	${EDITOR} "${file}"
	exit
}

function main {
	local delete_mode=false edit=false ignore_case=false history_file=${_DEFAULT_HISTORY_FILE} \
			gawk_args=() keywords=() regex_mode=false show_location=false word_mode=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-d|--delete)
			delete_mode=true
			;;
		-e*|-k*|--keyword|--keyword=*)
			get_opt_and_optarg "${@:1:2}"
			keywords+=("${OPTARG}")
			shift "${OPTSHIFT}"
			;;
		-E|--edit)
			edit=true
			;;
		-f*|--file|--file=*)
			get_opt_and_optarg "${@:1:2}"
			history_file=${OPTARG}
			shift "${OPTSHIFT}"
			;;
		-h|--help)
			show_usage_and_exit
			;;
		-i|--ignore-case)
			ignore_case=true
			;;
		-r|--regex)
			regex_mode=true
			;;
		-S|--show-location)
			show_location=true
			;;
		-w|--match-words)
			word_mode=true
			;;
		-V|--version)
			echo "${_VERSION}"
			exit 2
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

		shift
	done

	function check_conflicting_arguments {
		local option_name=$1
		shift

		for var in delete_mode ignore_case keywords regex_mode word_mode "$@"; do
			[[ -z ${!var+.} || ${!var} == false ]] || \
				die "Invalid arguments specified along with the ${option_name} option"
		done
	}

	if [[ ${show_location} == true ]]; then
		check_conflicting_arguments show-location edit
		echo "${history_file}"
		return 0
	fi

	if [[ ${edit} == true ]]; then
		check_conflicting_arguments edit show_location
		edit_history_file_and_exit "${history_file}"
	fi

	[[ -e ${history_file} ]] || die "History file doesn't exist: ${history_file}"
	[[ -f ${history_file} ]] || die "Histroy file not a file: ${history_file}"
	[[ -r ${history_file} ]] || die "Histroy file not readable: ${history_file}"

	if [[ ${delete_mode} == true ]]; then
		gawk_args=(-i inplace -v delete_mode=1)
		[[ ${keywords+.} ]] || die "Delete mode requires keywords to be specified."
	fi

	[[ ${ignore_case} == true ]] && gawk_args+=(-v ignore_case=1)
	[[ ${regex_mode} == true ]] && gawk_args+=(-v regex_mode=1)
	[[ ${word_mode} == true ]] && gawk_args+=(-v word_mode=1)

	exec gawk "${gawk_args[@]}" '
		BEGIN {
			if (ARGC > 2) {
				for (i = 2; i < ARGC; ++i) {
					negate[i] = ARGV[i] ~ /^!/
					keywords[i] = negate[i] ? substr(ARGV[i], 2) : ARGV[i]
				}

				ARGC = 2
			} else {
				show_all = 1
			}

			if (ignore_case && regex_mode)
				IGNORECASE = 1
		}

		/^#([[:digit:]]+$)/ {
			timestamp = $0
			next
		}

		{
			cmd = $0
			next_timestamp = ""

			if (timestamp) {
				lastRT = RT

				while (getline > 0) {
					if (/^#([[:digit:]]+$)/) {
						next_timestamp = $0
						break
					}

					cmd = cmd lastRT $0
					lastRT = RT
				}
			}

			if (cmd !~ /^\s*(#|hist\s*)/) {
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
						if (delete_mode)
							found = !found
						if (!found)
							next
					}
				}

				if (delete_mode) {
					if (timestamp)
						printf "%s%s", timestamp, ORS

					printf "%s%s", cmd, ORS
				} else {
					if (timestamp)
						printf "%5d  [%s] %s%s" , ++counter, strftime("%F %T %z", substr(timestamp, 2)),
								cmd, ORS
					else
						printf "%5d  %s%s", ++counter, cmd, ORS
				}
			}

			timestamp = next_timestamp
		}
	' "${history_file}" "${keywords[@]}"
}

main "$@"
