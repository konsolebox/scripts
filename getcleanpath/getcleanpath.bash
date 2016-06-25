function getcleanpath {
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

	__="/${T2[*]:0:I}"
}
