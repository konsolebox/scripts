# gdb-completion.bash
#
# Copyright (c) 2022 konsolebox
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
	declare -gA _GDB_COMP_OPT_CACHE=()
	_GDB_COMP_USE_STATIC_OPTS=${_GDB_COMP_USE_STATIC_OPTS-false}
	_GDB_COMP_SKIP_CHECK_ELF_EXECUTABLE=${_GDB_COMP_SKIP_CHECK_ELF_EXECUTABLE-false}
	declare -gA _GDB_COMP_EXECUTABLE_TEST_CACHE=()
	_GDB_PATH=

	if false; then
		function _gdb_comp_log_debug {
			logger -t gdb-completion -p debug -- "${FUNCNAME[1]-}${FUNCNAME[1]+: }$1"
		}
	fi

	function _gdb_comp_get_all_opts {
		if [[ ${_GDB_COMP_USE_STATIC_OPTS} == true ]]; then
			# From gdb 10.2
			__="--args --batch --batch-silent --cd --command --configuration --core --data-directory --dbx --directory --eval-command --exec --fullname --help --init-command --init-eval-command --interpreter --nh --nw --nx --pid --quiet --readnever --readnow --return-child-result --se --silent --symbols --tty --tui --version --write -D -GDB -arguments -b -directory -ex -file -id -iex -ix -l -line -q -related -w -x"
		else
			__=${_GDB_COMP_OPT_CACHE["all_opts|${_GDB_PATH}"]-}

			if [[ -z $__ ]]; then
				__=$(
					shopt -so pipefail
					"${_GDB_PATH}" --help 2>&1 | grep -Poe '-[[:alnum:]-]+' | sort -u
				) || return 1

				_GDB_COMP_OPT_CACHE["all_opts|${_GDB_PATH}"]=$__
			fi
		fi

		return 0
	}

	function _gdb_comp_get_opts_with_arg_expr {
		if [[ ${_GDB_COMP_USE_STATIC_OPTS} == true ]]; then
			# From gdb 10.2
			__="--core|--exec|--pid|--directory|--se|--symbols|--command|-x|--init-command|-ix|--eval-command|-ex|--init-eval-command|-iex|--interpreter|--tty|-b|-l|--cd|--data-directory|-D"
		else
			__=${_GDB_COMP_OPT_CACHE["opts_with_arg_expr|${_GDB_PATH}"]-}

			if [[ -z $__ ]]; then
				__=$(
					shopt -so pipefail

					"${_GDB_PATH}" --help 2>&1 | gawk -v ORS='|' '
						match($0, /^ *(-[[:alnum:]]+) [[:upper:]]+/, a) {
							print a[1]
							next
						}
						match($0, /(--[[:alnum:]-]+)=[[:upper:]]+(, (-[[:alnum:]-]+))?/, a) {
							print a[1]
							if (a[3])
								print a[3]
						}
					'
				) || return 1

				__=${__%'|'}
				_GDB_COMP_OPT_CACHE["opts_with_arg_expr|${_GDB_PATH}"]=$__
			fi
		fi

		return 0
	}

	function _gdb_comp_generate_filename_replies {
		local one_final_result=false temp i gen_type=${2-f}
		readarray -t COMPREPLY < <(compgen -"${gen_type}" -- "$1")

		while [[ ${#COMPREPLY[@]} -eq 1 && -d ${COMPREPLY} && -x ${COMPREPLY} ]]; do
			readarray -t temp < <(cd "${COMPREPLY}" &>/dev/null && compgen -"${gen_type}")
			[[ ${#temp[@]} -eq 0 ]] && break
			COMPREPLY=("${temp[@]/#/"${COMPREPLY%/}/"}")
		done

		[[ ${#COMPREPLY[@]} -eq 1 ]] && test -"${gen_type}" "${COMPREPLY}" && one_final_result=true

		for i in "${!COMPREPLY[@]}"; do
			[[ -d ${COMPREPLY[i]} ]] && COMPREPLY[i]=${COMPREPLY[i]%%+(/)}/
		done

		[[ ${one_final_result} == true ]]
	}

	function _gdb_comp_check_if_elf_executable {
		if [[ ${_GDB_COMP_SKIP_CHECK_ELF_EXECUTABLE} == true ]]; then
			return 0
		elif [[ ${_GDB_COMP_EXECUTABLE_TEST_CACHE[$1]+.} ]]; then
			[[ ${_GDB_COMP_EXECUTABLE_TEST_CACHE[$1]} == true ]]
		else
			local exec=false
			[[ ${1##*/} != *.so?(.*) && -x $1 ]] && read -rN4 magic < "$1" && \
					[[ ${magic} == $'\x7f'ELF ]] && exec=true
			_GDB_COMP_EXECUTABLE_TEST_CACHE[$1]=${exec}
			[[ ${exec} == true ]]
		fi
	}

	function _gdb_comp_generate_directory_or_executable_filename_replies {
		local magic unfiltered=() unquoted=() temp __
		local -A reg=()
		readarray -t unfiltered < <(compgen -f -- "$1")

		while [[ ${#unfiltered[@]} -eq 1 && -d ${unfiltered} && -x ${unfiltered} ]]; do
			readarray -t temp < <(cd "${unfiltered}" &>/dev/null && compgen -f)
			[[ ${#temp[@]} -eq 0 ]] && break
			unfiltered=("${temp[@]/#/"${unfiltered%/}/"}")
		done

		[[ $1 != */* ]] && readarray -t -O "${#unfiltered[@]}" unfiltered < <(compgen -c -- "$1")

		for __ in "${unfiltered[@]}"; do
			if [[ -z ${reg[$__]-} ]]; then
				if [[ -d $__ ]]; then
					[[ -x $__ ]] && unquoted+=("$__")
				elif [[ -e $__ ]]; then
					_gdb_comp_check_if_elf_executable "$__" && unquoted+=("$__")
				elif [[ $1 != */* ]]; then
					temp=$(type -P -- "$__") && _gdb_comp_check_if_elf_executable "${temp}" && \
							unquoted+=("$__")
				fi

				reg[$__]=.
			fi
		done

		COMPREPLY=()

		for __ in "${unquoted[@]}"; do
			[[ -d $__ ]] && ! { [[ $__ == */* ]] && type -P -- "$__" > /dev/null; } && __=${__%%+(/)}/
			printf -v "COMPREPLY[${#COMPREPLY[@]}]" %q "$__"
		done

		[[ ${#unquoted[@]} -eq 1 && ${unquoted} != */ ]]
	}

	function _gdb_comp_try_get_opt_with_arg {
		local -n __opt=$1 __arg=$2 __prefix=$3
		local i __
		_gdb_comp_get_opts_with_arg_expr || return 1

		for (( i = 1; i <= COMP_CWORD; ++i )); do
			set -- "${COMP_WORDS[@]:i:2}"

			if [[ i -eq COMP_CWORD && $1 == --* && $1 == @($__)=* ]]; then
				__arg=${1#*=} __prefix=${1:0:(${#1} - ${#__arg})} __opt=${__prefix%=}
				return 0
			elif [[ i -eq COMP_CWORD && ${#1} -gt 2 && $1 == -[!-]* && $1 == @($__)* ]]; then
				__arg=${1#*=} __prefix=${1:0:(${#1} - ${#__arg})} __opt=$__prefix
				return 0
			elif [[ $1 == @($__) ]]; then
				if (( i == COMP_CWORD - 1 )); then
					__opt=$1 __arg=$2 __prefix=
					return 0
				fi

				(( ++i ))
			fi
		done

		return 1
	}

	function _gdb_comp_try_complete_command {
		local COMP_CWORD=$1 COMP_LINE=$2 COMP_WORDS=("${@:2}") COMP_POINT=${#2}
		local comp_cmd comp_func=() comp_opts=() comp_opt_opts=() temp i __

		for (( i = 1; i < ${#COMP_WORDS[@]}; ++i )); do
			__=" ${COMP_WORDS[i]}"
			COMP_LINE+=$__
			[[ i -le COMP_CWORD ]] && (( COMP_POINT += ${#__} ))
		done

		__=$(complete -p "${COMP_WORDS}" 2>/dev/null) && [[ $__ ]] || return 1
		readarray -t comp_cmd < <(compgen -W "$__")

		for (( i = 1; i < ${#comp_cmd[@]}; ++i )); do
			if [[ ${comp_cmd[i]} == -[abcdefgjksuv] ]]; then
				comp_opts+=("${comp_cmd[i]}")
			elif [[ ${comp_cmd[i]} == -F ]]; then
				comp_func=("${comp_cmd[++i]}")
			elif [[ ${comp_cmd[i]} == [-+]o ]]; then
				comp_opts+=("${comp_cmd[i]}" "${comp_cmd[i + 1]}")
				comp_opt_opts+=("${comp_cmd[i]}" "${comp_cmd[i + 1]}")
				(( ++i ))
			elif [[ ${comp_cmd[i]} == -[AGWCXPS] ]]; then
				comp_opts+=("${comp_cmd[i]}" "${comp_cmd[i + 1]}")
				(( ++i ))
			fi
		done

		set -- "${COMP_CWORD}" "$(compgen -W "${COMP_WORDS[COMP_CWORD]}")" \
				"$(compgen -W "${COMP_WORDS[COMP_CWORD - 1]}")"

		[[ ${#comp_opt_opts[@]} -gt 0 ]] && compopt "${comp_opt_opts[@]}"
		[[ ${comp_func+.} ]] && "${comp_func}" "$@"
		readarray -t temp < <(compgen "${comp_opts[@]}" -- "$2")
		COMPREPLY+=("${temp[@]}")
		return 0
	}

	function _gdb_comp_current_word_open_quoted {
		local i

		for (( i = COMP_POINT - 1; i > 0; --i )); do
			[[ ${COMP_LINE:i:1} == [\"\'] ]] && return 0
			[[ ${COMP_LINE:i:1} == [${COMP_WORDBREAKS}] ]] && return 1
		done

		return 1
	}

	function _gdb_comp {
		COMPREPLY=()
		local args_opt_specified=false exec=() dont_add_space=false past_double_dash=false
		local arg exec_cword=0 opt prefix i __
		_GDB_PATH=$(type -p gdb) && [[ ${_GDB_PATH} ]] || return
		_gdb_comp_get_opts_with_arg_expr || return

		for (( i = 1; i < COMP_CWORD; ++i )); do
			if [[ ${past_double_dash} == true ]]; then
				if [[ -z ${exec+.} ]]; then
					exec=("${COMP_WORDS[i]}")
					exec_cword=0
				fi
			elif [[ ${COMP_WORDS[i]} == -- ]]; then
				past_double_dash=true
			elif [[ ${COMP_WORDS[i]} == --args ]]; then
				args_opt_specified=true
				exec=("${COMP_WORDS[@]:i + 1}")
				exec_cword=$(( COMP_CWORD - i - 1 ))
				break
			elif [[ ${COMP_WORDS[i]} == @($__) ]]; then
				(( ++i ))
			elif [[ ${COMP_WORDS[i]} != -* ]]; then
				if [[ -z ${exec+.} ]]; then
					exec=("${COMP_WORDS[i]}")
					exec_cword=0
				fi
			fi
		done

		if [[ ${#exec[@]} -gt 1 ]]; then
			if [[ ${args_opt_specified} == true ]] && \
					_gdb_comp_try_complete_command "${exec_cword}" "${exec[@]}"; then
				return 0
			else
				_gdb_comp_generate_filename_replies "$2" || dont_add_space=true
			fi
		elif [[ ${past_double_dash} == false ]] && \
				_gdb_comp_try_get_opt_with_arg opt arg prefix; then
			case ${opt} in
			-C|--directory|-I|--libdir|-R|--gdblibdir)
				_gdb_comp_generate_filename_replies "${arg}" d || dont_add_space=true
				;;
			-f|--gdbfile)
				_gdb_comp_generate_filename_replies "${arg}" || dont_add_space=true
				;;
			esac

			if [[ ${prefix} ]]; then
				for i in "${!COMPREPLY[@]}"; do
					COMPREPLY[i]=${prefix}${COMPREPLY[i]}
				done
			fi
		elif [[ ${past_double_dash} == false && $2 == -* ]]; then
			_gdb_comp_get_all_opts || return
			readarray -t COMPREPLY < <(compgen -W "$__" -- "$2")
		elif [[ $2 == [[:graph:]]* ]]; then
			_gdb_comp_generate_directory_or_executable_filename_replies "$2" || \
				dont_add_space=true
		fi

		if ! _gdb_comp_current_word_open_quoted; then
			for i in "${!COMPREPLY[@]}"; do
				printf -v "COMPREPLY[$i]" %q "${COMPREPLY[i]}"
			done
		fi

		[[ ${dont_add_space} == true ]] && compopt -o nospace
	}

	# Removing '=' is necessary since the equal sign still becomes stored as
	# a separate argument in COMP_WORDS.  Besides that, the equal sign can
	# also be a part of the filename and even though COMP_WORDS can be
	# recomposed using `compgen -W`, telling bash how the token should be
	# completed itself would require an ugly workaround since the token is
	# already split.  Perhaps the replies can be trimmed out so they don't
	# include the partial strings which aren't originally part of the token
	# being completed, but they would look terrible when displayed.  So
	# generally the added hack isn't worth it.
	#
	COMP_WORDBREAKS=${COMP_WORDBREAKS//=}

	complete -F _gdb_comp gdb
fi
