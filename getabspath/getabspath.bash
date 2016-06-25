function getabspath {
	local T1 T2=() I=0 IFS=/

	case $1 in
	/*)
		read -ra T1 <<< "${1#/}"
		;;
	*)
		read -ra T1 <<< "${PWD#/}/$1"
		;;
	esac

	for __ in "${T1[@]}"; do
		case $__ in
		..)
			[[ I -gt 0 ]] && (( --I ))
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
		[[ I -gt 0 ]] && __="/${T2[*]:0:I}/" || __=/
		;;
	*)
		[[ I -gt 0 ]] && __="/${T2[*]:0:I}" || __=/.
		;;
	esac
}
