#!/bin/bash

# ----------------------------------------------------------

# hist
#
# Finds entries in ~/.bash_history
#
# Usage: hist[.bash] [-h|--help|-V|--version] [--] [[!]keyword ...]]
#
# Author: konsolebox
# Copyright Free / Public Domain
# Nov. 19, 2024

# ----------------------------------------------------------

VERSION=2024.11.19

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

function die {
	printf '%s\n' "$1"
	exit "${2-1}"
}

function main {
	if [[ $1 == -h || $1 == --help ]]; then
		echo "Usage: $0 [-h|--help|-V|--version] [--] [[!]keyword ...]]"
		echo "Invalid options will also be considered as keywords."
		exit 2
	elif [[ $1 == -V || $1 == --version ]]; then
		echo "${VERSION}"
		exit 2
	fi

	[[ $1 == -- ]] && shift
	[[ -e ~/.bash_history ]] || die "History file doesn't exist."
	[[ -f ~/.bash_history ]] || die "Histroy file not a file."
	[[ -r ~/.bash_history ]] || die "Histroy file not readable."

	exec gawk '
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

			close(ARGV[1])
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
					for (i in keywords) {
						found = index(cmd, keywords[i])

						if (negate[i] ? found : !found)
							next
					}
				}

				if (timestamp)
					printf "%5d  [%s] %s%s" , ++counter, strftime("%F %T %z", substr(timestamp, 2)),
							cmd, ORS
				else
					printf "%5d  %s%s", ++counter, cmd, ORS
			}

			timestamp = next_timestamp
		}
	' ~/.bash_history "$@"
}

main "$@"
