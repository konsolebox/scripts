#!/bin/bash

# ----------------------------------------------------------

# hist
#
# Finds entries in ~/.bash_history
#
# Usage: hist[.bash] keyword [keyword2 ...]
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 7, 2024

# ----------------------------------------------------------

[ -n "${BASH_VERSION}" ] || {
	echo "This script requires Bash."
	exit 1
}

function die {
	printf '%s\n' "$1"
	exit "${2-1}"
}

function main {
	if [[ $# -eq 0 || $1 == -h || $1 == --help ]]; then
		echo "Usage: $0 [-h|--help] [--] keyword [keyword2 ...]"
		echo "Invalid options will also be considered as keywords."
		return 1
	fi

	[[ $1 == -- ]] && shift
	[[ -e ~/.bash_history ]] || die "History file doesn't exist."
	[[ -f ~/.bash_history ]] || die "Histroy file not a file."
	[[ -r ~/.bash_history ]] || die "Histroy file not readable."

	exec gawk '
		BEGIN {
			for (i = 2; i < ARGC; ++i) {
				negate[i] = ARGV[i] ~ /^!/
				keywords[i] = negate[i] ? substr(ARGV[i], 2) : ARGV[i]
			}

			ARGC = 2

			for (i = 0; i < 100; ++i) {
				if ((getline < ARGV[1]) < 1)
					break

				if ($0 ~ /^#[[:digit:]]+$/) {
					has_timestamps = 1
					RS = "#[[:digit:]]+\n"
					break
				}
			}

			close(ARGV[1])
		}

		!/^\s*(#|hist )/ {
			for (i in keywords) {
				found = index($0, keywords[i])

				if (negate[i] ? found : !found)
					next
			}

			if (has_timestamps)
				gsub(/\n$/, "")

			if (match(RT, /^#([[:digit:]]+)/, a))
				printf "%5d  [%s] %s\n", ++counter, strftime("%F %T %z", a[1]), $0
			else
				printf "%5d  %s\n", ++counter, $0
		}
	' ~/.bash_history "$@"
}

main "$@"
