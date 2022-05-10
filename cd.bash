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
# May 10, 2022
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

	if [[ $# -eq 0 ]]; then
		builtin cd -P "${opts[@]}" || return
	elif [[ $# -gt 1 ]]; then
		echo "Too many directory arguments specified." >&2
	elif [[ $1 == - && ${#DIRSTACK[@]} -gt 0 ]]; then
		if builtin cd -P "${opts[@]}" -- "${DIRSTACK[@]:(-1)}"; then
			popd -n > /dev/null
		else
			echo "Run 'popd -n' to exclude directory from the stack if it has issues." >&2
		fi

		return
	elif [[ $1 == . ]]; then
		builtin cd -P "${opts[@]}" -- "${PWD}" || return
		[[ ${#DIRSTACK[@]} -gt 0 ]] && popd -n > /dev/null
	else
		builtin cd -P "${opts[@]}" -- "$1" || return
	fi

	if [[ ${#DIRSTACK[@]} -eq 0 || ${PWD} != "${DIRSTACK[@]:(-1)}" ]]; then
		pushd -n -- "${PWD}" > /dev/null
	fi
}
