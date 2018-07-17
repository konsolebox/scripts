if
	(
		__=$PWD

		if [ -n "$__" ]; then
			for d in / /bin /dev /etc /home /lib /opt /run /usr /var /tmp; do
				if [ ! "$d" = "$__" ] && cd "$d"; then
					[ ! "$PWD" = "$__" ]
					exit "$?"
				fi
			done
		fi

		exit 1
	) >/dev/null 2>&1
then
	gwd() {
		__=$PWD
	}
elif ( [ "`type pwd`" = 'pwd is a shell builtin' ] ) >/dev/null 2>&1; then
	gwd() {
		__=`pwd`
	}
else
	gwd() {
		__=`exec pwd`
	}
fi
