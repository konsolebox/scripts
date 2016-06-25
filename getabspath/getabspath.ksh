function getabspath {
	typeset T1 T2 I=0 IFS=/
	[[ $1 == /* ]] && __=${1#/} || __=${PWD#/}/$1

	read -rA T1 << .
$__
.

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -gt 0 ]] && unset 'T2[--I]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		T2[I++]=$__
	done

	case $1 in
	*/)
		[[ I -gt 0 ]] && __="/${T2[*]}/" || __=/
		;;
	*)
		[[ I -gt 0 ]] && __="/${T2[*]}" || __=/.
		;;
	esac
}
