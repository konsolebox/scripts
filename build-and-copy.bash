#!/bin/bash

# ----------------------------------------------------------

# build-and-copy.bash
#
# This script automates building of initrd image using the
# files and directories in the current directory.
#
# It also accepts a '-m' option which makes it copy kernel
# modules to 'lib/modules' before creating the image.
#
# The initrd image is created in the parent directory and
# then copied to /boot.
#
# Usage: [bash] ./build-and-copy.bash [options]
#
# Author: konsolebox
# Copyright Free / Public Domain
# June 9, 2024

# Credits (Thanks to)
#
# tirnanog - For the `find . -name '.git*' -prune -o -print`
#            and `rsync -files-from=- -0` methods

# ----------------------------------------------------------

[ -n "${BASH_VERSION}" ] && [[ BASH_VERSINFO -ge 5 ]] || {
	echo "This script requires Bash version 5 or newer to run." >&2
	exit 1
}

set -f && set +o posix && set -o pipefail && shopt -s assoc_expand_once extglob lastpipe || exit 1

VERSION=2024.06.09

function show_usage_and_exit {
	echo "Creates an initrd image using files in current directory, saves it to parent
directory, and copies it to /boot

Usage: $0 [options]

Important Options:
  -r, --kernel-release RELEASE     Specify kernel's release name.  If this is
                                   omitted, the output of 'uname -r' is used.
  -m, --copy-modules [LIST]        Copy /lib/modules/RELEASE to lib/modules
                                   before creating the image.  A specific
                                   comma-separated list of modules can also be
                                   specified.  Only these specified modules
                                   along with their dependencies will be copied.
  -M, --copy-modules-file FILE     Same as '-m' but extracts list of modules to
                                   copy from FILE instead.  Each entry should be
                                   separated by a newline.  Empty lines and
                                   lines starting with '#' are ignored.
  -i, --ignore-inexistent-modules  Ignore specified modules that also aren't
                                   hard dependencies of other modules if they
                                   don't exist
  -z, --exclude-softdeps           Don't copy soft dependencies of modules

Other Options:
      --dry-run              Do not actually create anything.
  -l, --create-modules-list  Create a 'modules_list' file which will contain a
                             list of modules in 'lib/modules'
  -n, --no-backup            Do not create a backup of initrd file in /boot
                             before overriding it
  -h, --help                 Show this usage info and exit
  -V, --version              Show version and exit

The 'lib/modules' directory and the 'modules_list' file always get deleted
before any operation."
	exit 2
}

function fail {
	printf '%s\n' "$1" >&2
	exit "${2-1}"
}

function call {
	local dry_run=false

	if [[ ${1-} == --dry-run ]]; then
		dry_run=true
		shift
	fi

	if [[ ${_VERBOSE} == true ]]; then
		local q msg= __

		for __; do
			printf -v q %q "$__"

			if [[ $q == "$__" ]]; then
				msg+=" $__"
			elif [[ $__ == *\'* ]]; then
				msg+=" $q"
			else
				msg+=" '$__'"
			fi
		done

		printf '%s\n' "> ${msg# }" >&"${_CALL_MSG_FD}"
	fi

	[[ ${dry_run} == true ]] || command "$@"
}

function get_opt_and_optarg {
	local optional=false

	if [[ $1 == @optional ]]; then
		optional=true
		shift
	fi

	OPT=$1 OPTARG= OPTSHIFT=0

	if [[ $1 == -[!-]?* ]]; then
		OPT=${1:0:2} OPTARG=${1:2}
	elif [[ $1 == --*=* ]]; then
		OPT=${1%%=*} OPTARG=${1#*=}
	elif [[ ${2+.} && (${optional} == false || $2 != -?*) ]]; then
		OPTARG=$2 OPTSHIFT=1
	elif [[ ${optional} == true ]]; then
		return 1
	else
		fail "No argument specified for '$1'." 2
	fi

	return 0
}

function call_func_or_block {
	if [[ $1 == *[[:space:]]* ]]; then
		eval "shift; $1"
	else
		"$@"
	fi
}

function with_opened_file {
	local __file=$1 __fd
	exec {__fd}< "${__file}" || fail "Failed to open '${__file}' for reading."
	call_func_or_block "$2" "${__fd}"
	exec {__fd}<&- || fail "Failed to close FD ${__fd}."
}

function get_module_files {
	module_files=()
	local modules_dir=$1 dep deps file ignore_inexistent=false exclude_softdeps=false mod
	local -A modules_alias_map=() modules_builtin_reg=() modules_dep_map=() modules_dep_reg=() \
			modules_map=() modules_map_rev=() modules_reg=() modules_softdep_map=() specified=()
	shift

	if [[ $1 == --exclude-softdeps ]]; then
		exclude_softdeps=true
		shift
	fi

	if [[ $1 == --ignore-inexistent ]]; then
		ignore_inexistent=true
		shift
	fi

	with_opened_file "${modules_dir}/modules.order" '
		local fd=$1 file mod

		while read -ru "${fd}" file; do
			mod=${file##*/} mod=${mod%.ko} mod=${mod//_/-}
			modules_map[${mod}]=${file}
			modules_map_rev[${file}]=${mod}
		done
	'

	with_opened_file "${modules_dir}/modules.alias" '
		local fd=$1 line

		while read -ru "${fd}" -a line; do
			[[ ${line} == alias ]] && modules_alias_map[${line[1]//_/-}]=${line[2]//_/-}
		done
	'

	with_opened_file "${modules_dir}/modules.builtin" '
		local fd=$1 file mod

		while read -ru "${fd}" file; do
			mod=${file##*/} mod=${mod%.ko} mod=${mod//_/-}
			modules_builtin_reg[${mod}]=.
		done
	'

	with_opened_file "${modules_dir}/modules.dep" '
		local fd=$1 file deps

		while read -ru "${fd}" file deps; do
			file=${file%:}
			mod=${file##*/} mod=${mod%.ko} mod=${mod//_/-}

			if [[ -z ${modules_map[${mod}]+.} ]]; then
				modules_map[${mod}]=${file}
				modules_map_rev[${file}]=${mod}
			fi

			modules_dep_map[${file}]=${deps}
		done
	'

	if [[ ${exclude_softdeps} == false ]]; then
		with_opened_file "${modules_dir}/modules.softdep" '
			local fd=$1 line mod deps

			while read -ru "${fd}" -a line; do
				if [[ ${line} == softdep ]]; then
					for (( i = 2; i < ${#line[@]}; ++i )); do
						[[ ${line[i]} == @(pre|post): ]] && unset "line[i]"
					done

					mod=${line[1]} line=("${line[@]:2}")
					modules_softdep_map[${mod//_/-}]=${line[*]//_/-}
				fi
			done
		'
	fi

	for mod; do
		mod=${mod//_/-} mod=${modules_alias_map[${mod}]-${mod}}
		specified[${mod}]=.
	done

	while mod=${1-}; shift; do
		mod=${mod//_/-} mod=${modules_alias_map[${mod}]-${mod}}

		if [[ -z ${modules_reg[${mod}]+.} ]]; then
			modules_reg[${mod}]=.
			file=${modules_map[${mod}]-}

			if [[ ${file} ]]; then
				deps=()

				for file in ${modules_dep_map[${file}]-}; do
					dep=${modules_map_rev[${file}]-}
					[[ ${dep} ]] || fail "Module file not mapped to a name: ${file}"
					deps+=("${dep}")
					modules_dep_reg[${modules_alias_map[${dep}]-${dep}}]=.
				done

				[[ ${exclude_softdeps} == false ]] && deps+=(${modules_softdep_map[${mod}]-})
				[[ ${deps+.} ]] && set -- "$@" "${deps[@]}"
			fi
		fi
	done

	for mod in "${!modules_reg[@]}"; do
		if [[ -z ${modules_builtin_reg[${mod}]+.} ]]; then
			file=${modules_map[${mod}]-}

			if [[ -z ${file} ]]; then
				[[ ${ignore_inexistent} == true && ${specified[${mod}]+.} && \
						-z ${modules_dep_reg[${mod}]+.} ]] && continue
				fail "Module not mapped to a file: ${mod}"
			fi

			file=${modules_dir}/${file}
			[[ -e ${file} ]] || fail "Module exists in modules.order but not in filesystem: ${file}"
			module_files+=("${file}")
		fi
	done
}

function main {
	local copy_modules=() copy_all_modules=false create_modules_list=false do_backup=true \
			dry_run=() exclude_softdeps=false file IFS=$' \t\n' ignore_inexistent_modules=false \
			kernel_release= mod module_files module_files_sorted non_module_files=()

	[[ ${PWD} -ef / ]] && fail "Refusing to run in '/'."

	while [[ $# -gt 0 ]]; do
		case $1 in
		-i|--ignore-inexistent-modules)
			ignore_inexistent_modules=true
			;;
		-l|--create-modules-list)
			create_modules_list=true
			;;
		-m*|--copy-modules?(=*))
			if get_opt_and_optarg @optional "${@:1:2}"; then
				IFS=, eval 'copy_modules+=(${OPTARG})'
				shift "${OPTSHIFT}"
			elif [[ -z ${copy_modules+.} ]]; then
				copy_modules=('*')
			fi
			;;
		-M*|--copy-modules-file?(=*))
			get_opt_and_optarg "${@:1:2}"

			with_opened_file "${OPTARG}" $'
				local fd=$1 line entry_added=false

				while read -ru "${fd}" line; do
					[[ -z ${line} || ${line} == "#"* ]] && continue
					copy_modules+=("${line}") entry_added=true
				done

				[[ ${entry_added} == false ]] && \
					echo "Warning: No module entry found in \'${OPTARG}\'."
			'

			shift "${OPTSHIFT}"
			;;
		-n|--no-backup)
			do_backup=false
			;;
		-N|--dry-run)
			dry_run=(--dry-run)
			;;
		-r*|--kernel-release?(=*))
			get_opt_and_optarg "${@:1:2}"
			kernel_release=${OPTARG}
			shift "${OPTSHIFT}"
			;;
		-z|--exclude-softdeps)
			exclude_softdeps=true
			;;
		-h|--help)
			show_usage_and_exit
			;;
		-V|--version)
			echo "${VERSION}"
			return 2
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		*)
			fail "Invalid argument: $1" 2
			;;
		esac

		shift
	done

	[[ ${dry_run-} ]] && echo "Dry run enabled."

	[[ ${create_modules_list} == true && ${copy_modules} == false ]] && \
		fail "Create-modules-list option requires copy-modules option."

	if [[ ${copy_modules+.} ]]; then
		for mod in "${copy_modules[@]}"; do
			case ${mod} in
			'*')
				copy_all_modules=true
				;;
			''|[-_]*|*[-_]|*[^[:alnum:]:_-]*)
				fail "Invalid module name: ${mod}"
				;;
			esac
		done
	elif [[ ${create_modules_list} == true ]]; then
		fail "Create-modules-list option requires modules are copied."
	fi

	if [[ -z ${kernel_release} ]]; then
		kernel_release=$(uname -r) && [[ -n ${kernel_release} ]] || \
			fail "Failed to get current kernel release."

		echo "Using current kernel release which is '${kernel_release}'."
	fi

	for file in lib/modules modules_list; do
		if [[ -e ${file} ]]; then
			echo "Deleting '${file}'."
			call "${dry_run[@]}" rm -fr -- "${file}" && [[ ${dry_run-} || ! -e ${file} ]] || \
				fail "Failed to delete '${file}'."
		fi
	done

	if [[ ${copy_modules+.} ]]; then
		echo "Creating 'lib/modules'."

		[[ -d /lib/modules/${kernel_release} ]] || \
			fail "Modules directory '/lib/modules/${kernel_release}' does not exist."

		if [[ ${copy_all_modules} == true ]]; then
			call "${dry_run[@]}" mkdir -p lib/modules || fail "Failed to create 'lib/modules'."

			echo "Copying '/lib/modules/${kernel_release}' to 'lib/modules'."
			call "${dry_run[@]}" cp -a "/lib/modules/${kernel_release}" lib/modules/ || \
				fail "Failed to copy '/lib/modules/${kernel_release}' to 'lib/modules'."
		else
			call "${dry_run[@]}" mkdir -p "lib/modules/${kernel_release}" || \
				fail "Failed to create 'lib/modules/${kernel_release}'."

			local opts=()
			[[ ${exclude_softdeps} == true ]] && opts+=(--exclude-softdeps)
			[[ ${ignore_inexistent_modules} == true ]] && opts+=(--ignore-inexistent)
			get_module_files "/lib/modules/${kernel_release}" "${opts[@]}" "${copy_modules[@]}"

			readarray -t non_module_files < <(find "/lib/modules/${kernel_release}" -type f \
					-not -name '*.ko')
			[[ ${non_module_files+.} ]] || \
				fail "No non-module files found in '/lib/modules/${kernel_release}'."

			echo "Copying module files to 'lib/modules/${kernel_release}'."
			printf '%s\n' "${module_files[@]##*/}" | sort | readarray -t module_files_sorted
			printf 'Modules: %s\n' "${module_files_sorted[*]}"

			if [[ -z ${dry_run-} ]]; then
				printf '%s\0' "${module_files[@]}" "${non_module_files[@]}" | \
						rsync -Ra --files-from=- -0 / . || fail "Failed to copy files using rsync."
			fi
		fi

		if [[ ${create_modules_list} == true ]]; then
			echo "Creating 'modules_list'."

			if [[ -z ${dry_run-} ]]; then
				find "/lib/modules/${kernel_release}" -name '*.ko' | \
						gawk -F '[/.]' '{ print $(NF - 1) }' | sort -u > modules-list || \
					fail "Failed to create 'modules-list'."
			fi
		fi
	fi

	local build=initramfs-${kernel_release}
	echo "Creating CPIO archive '../${build}'."

	if [[ -z ${dry_run-} ]]; then
		find . -name '.git*' -prune -o -print | sort | cpio -o -H newc | \
				xz --check=none -z -f -9 -c > "../${build}" || \
			fail "Failed to create CPIO archive '../${build}'."
	fi

	if [[ ${do_backup} == true && -e /boot/${build} ]]; then
		echo "Backing up '/boot/${build}' as '/boot/${build}.bak'."
		call "${dry_run[@]}" cp -a "/boot/${build}"{,.bak} || \
			fail "Failed to create '/boot/${build}.bak'."
	fi

	echo "Copying '../${build}' to '/boot/'."
	call "${dry_run[@]}" cp -a "../${build}" "/boot/" || \
		fail "Failed to copy '../${build}' to '/boot/'."
}

main "$@"
