# ----------------------------------------------------------------------
# cd.bash
#
# Provides a convenient enhancement wrapper for the builtin cd command
# so it dynamically uses the directory stack instead of just OLDPWD.
# The wrapper also makes directories physically resolved by default.
# If '.' is specified, the value of "$PWD" is passed instead.  This is
# useful when currently directory's mount status has been updated.
# Always converting relative paths to complete paths has been considered
# but not doing it is thought to be the safer choice.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 13, 2022
#
# ----------------------------------------------------------------------

function cd {
	local args=() opts=()

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

			if builtin cd -P "${opts[@]}" -- "${@}"; then
				[[ ${DIRSTACK[0]} == "${DIRSTACK[1]}" ]] && popd -n
				return 0
			fi

			popd -n
		fi
	} > /dev/null

	return 1
}
