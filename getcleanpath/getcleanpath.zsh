function getcleanpath {
	local t i=0 IFS=/
	set -A t

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
			(( i )) && t[i--]=()
			continue
			;;
		.|'')
			continue
			;;
		esac

		t[++i]=$__
	done

	__="/${t[*]}"
}
