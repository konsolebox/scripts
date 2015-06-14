function getcleanpath {
	typeset T1 T2 I=0 IFS=/

	case $1 in
	/*)
		read -r -A T1 << .
$1
.
		;;
	*)
		read -r -A T1 << .
${PWD}/$1
.
		;;
	esac

	set -A T2

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

	__="/${T2[*]}"
}
