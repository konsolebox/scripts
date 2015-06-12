function getabspath {
	local T1 T2=() I=0 IFS=/

	case $1 in
	/*)
		read -r -a T1 <<< "$1"
		;;
	*)
		read -r -a T1 <<< "/${PWD}/$1"
		;;
	esac

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -ne 0 ]] && unset 'T2[--I]'
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
		[[ I -ne 0 ]] && __="/${T2[*]}/" || __=/
		;;
	*)
		[[ I -ne 0 ]] && __="/${T2[*]}" || __=/.
		;;
	esac
}
