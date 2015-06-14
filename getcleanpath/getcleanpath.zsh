function getcleanpath {
	local TOKENS I IFS=/ T
	set -A TOKENS

	__=$1

	case $1 in
	/*)
		set -- ${=1}
		;;
	*)
		set -- ${=PWD} ${=1}
		;;
	esac

	for T; do
		case $T in
		..)
			[[ I -ne 0 ]] && TOKENS[I--]=()
			continue
			;;
		.|'')
			continue
			;;
		esac

		TOKENS[++I]=$T
	done

	case $__ in
	*/)
		[[ I -ne 0 ]] && __="/${TOKENS[*]}/" || __=/
		;;
	*)
		[[ I -ne 0 ]] && __="/${TOKENS[*]}" || __=/.
		;;
	esac
}
