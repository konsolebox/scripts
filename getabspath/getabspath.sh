getabspath() {
	case $1 in
	/*)
		__=$1
		;;
	*)
		__=`exec pwd`/$1
		;;
	esac

	__=`_getabspath_in`

	case $1 in
	*/)
		[ ! "$__" = / ] && __=$__/
		;;
	*)
		[ "$__" = / ] && __=/.
		;;
	esac
}

_getabspath_in() {
	set -f
	IFS=/
	set -- $__

	while :; do
		__='' L=''

		for A; do
			shift

			case "$A" in
			..)
				[ -z "$L" ] && continue
				shift "$#"
				set -- $__ "$@"
				continue 2
				;;
			.|'')
				continue
				;;
			esac

			[ -n "$L" ] && __=$__/$L
			L=$A
		done

		__=$__/$L

		break
	done

	echo "$__"
}
