# rake-completion.bash
#
# Copyright (c) 2021 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

if [[ BASH_VERSINFO -ge 5 ]]; then
	declare -gA _RAKE_COMP_CACHE=()
	_RAKE_COMP_USE_STATIC_OPTS=${_RAKE_COMP_USE_STATIC_OPTS-false}
	_RAKE_PATH=

	if false; then
		function _rake_comp_log_debug {
			logger -t rake-completion -p debug -- "${FUNCNAME[1]-}${FUNCNAME[1]+: }$1"
		}
	fi

	function _rake_comp_get_all_opts {
		if [[ ${_RAKE_COMP_USE_STATIC_OPTS} == true ]]; then
			# From rake 13.0.6
			__="-A -B -C -D -E -G -H -I -N -P -R -T -V -W -X -e -f -g -h -j -m -n -p -q -r -s -t -v --all --backtrace --build-all --comments --describe --directory --dry-run --execute --execute-continue --execute-print --help --jobs --job-stats --libdir --multitask --nosearch --nosystem --no-deprecation-warnings --no-search --no-system --prereqs --quiet --rakefile --rakelib --rakelibdir --require --rules --silent --suppress-backtrace --system --tasks --trace --verbose --version --where"
		else
			__=${_RAKE_COMP_CACHE["all_opts|${_RAKE_PATH}"]-}

			if [[ -z $__ ]]; then
				__=$(
					shopt -so pipefail

					"${_RAKE_PATH}" --help 2>&1 | awk -F '[ =,]+' '
						p {
							for (i = 2; i <= NF; ++i) {
								if ($i ~ /^-/) {
									print $i
								} else {
									break
								}
							}
						}
						/Opt/ { p = 1 }
					'
				) || return 1

				_RAKE_COMP_CACHE["all_opts|${_RAKE_PATH}"]=$__
			fi
		fi

		return 0
	}

	function _rake_comp_get_opts_with_arg_expr {
		if [[ ${_RAKE_COMP_USE_STATIC_OPTS} == true ]]; then
			# From rake 13.0.6
			__="--backtrace|--job-stats|--suppress-backtrace|-C|--directory|-D|--describe|-e|--execute|-E|--execute-continue|-f|--rakefile|-I|--libdir|-j|--jobs|-p|--execute-print|-r|--require|-R|--rakelibdir|-t|--trace|-T|--tasks|-W|--where"
		else
			__=${_RAKE_COMP_CACHE["opts_with_arg_expr|${_RAKE_PATH}"]-}

			if [[ -z $__ ]]; then
				__=$(
					shopt -so pipefail

					"${_RAKE_PATH}" --help 2>&1 | awk -F '[ =,]+' -v ORS='|' '
						p {
							delete t
							for (i = 2; i <= NF; ++i)
								if ($i ~ /^-/) {
									t[i] = $i
								} else {
									if ($i ~ /^\[?[A-Z]+\]?$/)
										for (j in t)
											print t[j]
									break
								}
						}
						/Opt/ { p = 1 }
					'
				) || return 1

				__=${__%'|'}
				_RAKE_COMP_CACHE["opts_with_arg_expr|${_RAKE_PATH}"]=$__
			fi
		fi

		return 0
	}

	function _rake_comp_target_likely_specified {
		local opts_with_arg_expr= i __
		_rake_comp_get_opts_with_arg_expr && opts_with_arg_expr=$__

		for (( i = 1; i < ${#COMP_WORDS[@]}; ++i )); do
			case ${COMP_WORDS[i]} in
			--)
				break
				;;
			+([a-z0-9_])?(:)*)
				[[ i -ne COMP_CWORD ]] && return 0
				;;
			${opts_with_arg_expr})
				(( ++i ))
				;;
			esac
		done

		return 1
	}

	function _rake_comp_get_specified_rakefile {
		local opts_with_arg_expr=
		_rake_comp_get_opts_with_arg_expr && opts_with_arg_expr=$__
		set -- "${COMP_WORDS[@]}"
		__=

		while shift; [[ $# -gt 0 && $1 != -- ]]; do
			case $1 in
			-f|--rakefile)
				__=$2
				shift
				;;
			-f*|--rakefile=*)
				__=${1#@(-f|--rakefile=)}
				;;
			${opts_with_arg_expr})
				shift
				;;
			esac
		done

		[[ $__ && -f $__ ]]
	}

	function _rake_comp_default_rakefile_exists {
		local IFS=/

		if [[ $- == *f* ]]; then
			set -- ${PWD}
		else
			set -f
			set -- ${PWD}
			set +f
		fi

		while [[ $# -gt 0 ]]; do
			[[ -e "$*/Rakefile" ]] && return 0
			set -- "${@:1:$# - 1}"
		done

		return 1
	}

	function _rake_comp_generate_filename_replies {
		local one_file_result=false temp i
		readarray -t COMPREPLY < <(compgen -f -- "$1")

		while [[ ${#COMPREPLY[@]} -eq 1 && -d ${COMPREPLY} && -x ${COMPREPLY} ]]; do
			readarray -t temp < <(cd "${COMPREPLY}" &>/dev/null && compgen -f)
			[[ ${#temp[@]} -eq 0 ]] && break
			COMPREPLY=("${temp[@]/#/"${COMPREPLY%/}/"}")
		done

		[[ ${#COMPREPLY[@]} -eq 1 && -f ${COMPREPLY} ]] && one_file_result=true

		for i in "${!COMPREPLY[@]}"; do
			[[ -d ${COMPREPLY[i]} ]] && COMPREPLY[i]=${COMPREPLY[i]%%+(/)}/
			printf -v "COMPREPLY[$i]" %q "${COMPREPLY[i]}"
		done

		[[ ${one_file_result} == true ]]
	}

	function _rake_comp {
		local dont_add_space=false partial opt i __
		shopt -q extglob || return
		_RAKE_PATH=$(type -p rake) && [[ ${_RAKE_PATH} ]] || return
		_rake_comp_get_opts_with_arg_expr || return
		COMPREPLY=()

		if [[ $2 != -* && ${3-} != @($__) ]] && ! _rake_comp_target_likely_specified; then
			if _rake_comp_get_specified_rakefile; then
				__=$("${_RAKE_PATH}" -f "$__" --tasks 2>&1 | \
						awk '$1 == "rake" && / # / { print $2 }')
				[[ $__ ]] && readarray -t COMPREPLY < <(compgen -W "$__" -- "$2")
			elif _rake_comp_default_rakefile_exists; then
				__=$("${_RAKE_PATH}" --tasks 2>&1 | awk '$1 == "rake" && / # / { print $2 }')
				[[ $__ ]] && readarray -t COMPREPLY < <(compgen -W "$__" -- "$2")
			elif [[ ${#COMP_WORDS[@]} -eq 2 && -z $2 ]]; then
				_rake_comp_get_all_opts || return
				readarray -t COMPREPLY < <(compgen -W "$__" -- "$2")
			fi
		elif [[ $2 == @(-f*|--rakefile=*) ]]; then
			partial=${2#@(-f|--rakefile=)} opt=${2:0:(${#2} - ${#partial})}
			_rake_comp_generate_filename_replies "${partial}" || dont_add_space=true

			for i in "${!COMPREPLY[@]}"; do
				COMPREPLY[i]=${opt}${COMPREPLY[i]}
			done
		elif [[ ${3-} == @(-f|--rakefile) ]]; then
			_rake_comp_generate_filename_replies "$2" || dont_add_space=true
		elif [[ $2 == - || $2 == -? || $2 == --* && $2 != *=* ]]; then
			_rake_comp_get_all_opts || return
			readarray -t COMPREPLY < <(compgen -W "$__" -- "$2")
		fi

		[[ ${#COMPREPLY[@]} -eq 1 && ${dont_add_space} == false ]] && COMPREPLY+=' '
	}

	# Excluding ':' from COMP_WORDBREAKS is necessary so tasks that are named
	# with a colon can be recognized, but it conflicts with other completion
	# implementations that require it like git's contrib/git-completion.bash.
	#
	# Comment out the following line if the conflict needs to be avoided.
	#
	COMP_WORDBREAKS=${COMP_WORDBREAKS//:}

	# Removing '=' is also necessary since the equal sign still becomes stored
	# as a separate argument in COMP_WORDS.  Besides that, the equal sign can
	# also be a part of the filename and even though COMP_WORDS can be
	# recomposed using `compgen -W`, telling bash how the token should be
	# completed itself would require an ugly workaround since the token is
	# already split.  Perhaps the replies can be trimmed out so they don't
	# include the partial strings which aren't originally part of the token
	# being completed, but they would look terrible when displayed.  So
	# generally the added hack isn't worth it.
	#
	COMP_WORDBREAKS=${COMP_WORDBREAKS//=}

	complete -F _rake_comp -o nospace rake
fi
