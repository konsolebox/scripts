# ----------------------------------------------------------------------
#
# cd.bash
#
# Provides an enhancement wrapper for the builtin cd command.
#
# - It refers to the directory stack first before the OLDPWD variable.
# - Resolves directories to their physical versions by default.
# - If '.' is specified, the value of "$PWD" is passed instead.
# - If multiple directory arguments are passed and shell is interactive,
#   the user is asked to select one.
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 17, 2024
#
# ----------------------------------------------------------------------

function cd {
	local args=() opts=() __

	while [[ $# -gt 0 ]]; do
		case $1 in
		--)
			args+=("${@:2}")
			break
			;;
		-?*)
			opts+=("$1")
			;;
		*)
			args+=("$1")
			;;
		esac

		shift
	done

	set -- "${args[@]}"

	{
		if [[ $# -gt 1 && $- == *i* && -t 0 && -t 2 ]]; then
			echo "Choose a directory." >&2

			select __; do
				if [[ $__ ]]; then
					set -- "$__"
					break
				fi
			done
		fi

		if [[ $# -gt 1 ]]; then
			echo "Too many directory argmuments specified." >&2
		elif [[ ${1-} == - && ${#DIRSTACK[@]} -ge 2 ]]; then
			if builtin cd -P "${opts[@]}" -- "${DIRSTACK[1]}"; then
				popd -n
				return 0
			fi

			echo "Run 'popd -n' to exclude directory from the stack if it has issues." >&2
		else
			pushd -n -- "${PWD}"
			[[ ${1-} == . ]] && set -- "${PWD}"

			if builtin cd -P "${opts[@]}" -- "$@"; then
				[[ ${DIRSTACK[0]} == "${DIRSTACK[1]}" ]] && popd -n
				return 0
			fi

			popd -n
		fi
	} > /dev/null

	return 1
}
