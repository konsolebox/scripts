function getcleanpath {
	local T I=0 IFS=/
	set -A T

	case $1 in
	/*)
		set -- ${=1#/}
		;;
	*)
		set -- ${=PWD#/} ${=1}
		;;
	esac

	for __; do
		case $__ in
		..)
			[[ I -gt 0 ]] && T[I--]=()
			continue
			;;
		.|'')
			continue
			;;
		esac

		T[++I]=$__
	done

	__="/${T[*]}"
}
