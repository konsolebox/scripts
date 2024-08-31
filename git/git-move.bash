#!/bin/bash

# ------------------------------------------------------------------------------
#
# git-move
#
# Moves commits in a "context" to a new base commit within the same context
#
# The context can be a branch or simply a commit representing itself and the
# chain of commits behind it.
#
# Usage: git-move[.bash] [--context branch|commit] [--onto commit] commit...
#
# This tool requires git.
#
# Copyright (c) 2024 konsolebox
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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ------------------------------------------------------------------------------

[ -n "${BASH_VERSION}" ] && [[ BASH_VERSINFO -ge 5 ]] || {
	echo "Bash version 5.0 or newer is required to run this script."
	exit 1
}

set -f +m +o posix -o pipefail && shopt -s assoc_expand_once extglob lastpipe || exit 1

_CALL_MSG_FD=2
_DRY_RUN=()
_ORIG_HEAD_COMMIT=
_ORIG_HEAD_REF=
_TEMPORARY_BRANCH_NAME=
_TOP_LEVEL_DIR=
_VERBOSE=false
_VERSION=2024.08.31

function err {
	printf '%s\n' "$1" 2>&1
	return "${2-1}"
}

function die {
	err "$@"
	exit
}

function assert {
	eval "[[ $1 ]]" || die "Failed assertion: $1"
}

function get_opt_and_optarg {
	OPT=$1 OPTARG= OPTSHIFT=0

	if [[ $1 == -[!-]?* ]]; then
		OPT=${1:0:2} OPTARG=${1:2}
	elif [[ $1 == --*=* ]]; then
		OPT=${1%%=*} OPTARG=${1#*=}
	elif [[ ${2+.} ]]; then
		OPTARG=$2 OPTSHIFT=1
	else
		die "No argument specified for '$1'."
	fi

	return 0
}

function show_usage {
	echo "Moves commits in a \"context\" to a new base commit within the same context

The context can be a branch or simply a commit representing itself and the chain
of commits behind it.

Usage: $0 [options] commits...
       $0 -h|--help|-V|--version

Options:
  -c, --context CONTEXT  Reference to a branch or a commit that leads all commits
                         that are to be rearranged including itself.  If CONTEXT
                         is a branch, its reference will be updated to the
                         resulting HEAD unless -s or --stay-detached is
                         specified.  This defaults to the current branch or the
                         commit referred to by HEAD.
  -h, --help             Show this usage info and exit
  -n, --dry-run          Don't make actual changes
  -o, --onto BASE        Reference to the base commit that specified commits
                         will be moved onto.  This defaults to the resolved
                         reference of CONTEXT.
  -s, --stay-detached    Stay detached after successfully rearranging commits
                         and don't save resulting HEAD reference to CONTEXT when
                         CONTEXT is a reference to a branch
  -v, --verbose          Be verbose
  -V, --version          Show version and exit
  -w, --within CONTEXT   Same as specifying -c or --context"
}

function do_basic_reference_check {
	local __

	for __; do
		[[ $__ ]] || die "Reference cannot be empty."
		[[ $__ == -* ]] && die "Reference cannot begin with a dash: $__"
	done
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

	[[ ${dry_run} == true ]] || "$@"
}

function remove_move_orig_head {
	call "${_DRY_RUN[@]}" git update-ref MOVE_ORIG_HEAD -d --no-deref || \
		err "Failed to remove MOVE_ORIG_HEAD reference."
}

function is_branch_ref {
	[[ $1 == refs/heads/+([!/]) ]]
}

function abort {
	err "$1"

	if [[ -e ${_TOP_LEVEL_DIR}/.git/CHERRY_PICK_HEAD ]]; then
		git cherry-pick --quit || \
			die "Failed to discard CHERRY_PICK_HEAD."
	fi

	if is_branch_ref "${_ORIG_HEAD_REF}"; then
		call git switch "${_ORIG_HEAD_REF#refs/heads/}" --discard-changes || \
			die "Failed to switch back to \"${_ORIG_HEAD_REF}\" and discard changes."
	else
		call git reset --hard || \
			die "Failed to discard changes."
		call git checkout "${_ORIG_HEAD_COMMIT}" --detach || \
			die "Failed to switch back to \"${_ORIG_HEAD_COMMIT}\"."
	fi

	remove_move_orig_head || exit 1

	if [[ ${_TEMPORARY_BRANCH_NAME} && -e ${_TOP_LEVEL_DIR}/.git/${_TEMPORARY_BRANCH_NAME} ]]; then
		call git branch -D "${_TEMPORARY_BRANCH_NAME}" || \
			die "Failed to remove \"${_TEMPORARY_BRANCH_NAME}\" branch."
	fi

	exit 1
}

function validate_non_range_commit_argument {
	local name=$1 arg=$2
	[[ ${arg} == *@(..|^@)* ]] && die "Argument for \"${name}\" cannot be a range."
	[[ ${arg} == ^* ]] && die "Argument for \"${name}\" cannot be a negation."
	[[ ${arg} == *@(..|^@)* ]] && die "Argument for \"${name}\" cannot be a range."
	[[ ${arg} == *'^{'*'}' && ${arg} != *"^{commit}"* ]] && \
		die "Only commit types are allowed for \"${name}\"."
}

# https://github.com/git/git/blob/3a06386e314565108ad56a9bdb8f7b80ac52fb69/wt-status.c#L1772
# https://github.com/git/git/blob/43c8a30d150ecede9709c1f2527c8fba92c65f40/wt-status.c#L1702

function merge_in_progress {
	[[ -e ${_TOP_LEVEL_DIR}/.git/MERGE_HEAD ]]
}

function am_in_progress {
	[[ -e ${_TOP_LEVEL_DIR}/.git/rebase-apply/applying ]]
}

function rebase_in_progress {
	local git=${_TOP_LEVEL_DIR}/.git
	[[ -e ${git}/rebase-apply && ! ${git}/rebase-apply/applying ||
			-e ${git}/rebase-merge && ! ${git}/rebase-merge/interactive ]]
}

function interactive_rebase_in_progress {
	local git=${_TOP_LEVEL_DIR}/.git
	[[ -e ${git}/rebase-merge && ${git}/rebase-merge/interactive ]]
}

function cherry_pick_in_progress {
	[[ -e ${_TOP_LEVEL_DIR}/.git/CHERRY_PICK_HEAD ]]
}

function revert_in_progress {
	[[ -e ${_TOP_LEVEL_DIR}/.git/REVERT_HEAD ]]
}

function main {
	local commit commit_args=() context=() onto=() stay_detached=false __

	while [[ $# -gt 0 ]]; do
		case $1 in
		-c*|--context?(=*)|-w*|--within?(=*))
			get_opt_and_optarg "${@:1:2}"
			context=${OPTARG}
			shift "${OPTSHIFT}"
			;;
		-h|--help|-\?)
			show_usage
			return 2
			;;
		-n|--dry-run)
			_DRY_RUN=(--dry-run)
			;;
		-o*|--onto?(=*))
			get_opt_and_optarg "${@:1:2}"
			onto=${OPTARG}
			shift "${OPTSHIFT}"
			;;
		-s|--stay-detached)
			stay_detached=true
			;;
		-v|--verbose)
			_VERBOSE=true
			;;
		-V|--version)
			echo "${_VERSION}"
			return 2
			;;
		--)
			commit_args+=("${@:2}")
			break
			;;
		-[!-][!-]*)
			set -- "${1:0:2}" "-${1:2}" "${@:2}"
			continue
			;;
		-?*)
			die "Invalid option: $1" 2
			;;
		[[:alnum:]]*)
			commit_args+=("$1")
			;;
		*)
			die "Invalid argument: $1" 2
			;;
		esac

		shift
	done

	[[ ${commit_args+.} ]] || die "No commit specified."
	do_basic_reference_check "${commit_args[@]}" "${onto[@]}" "${context[@]}"

	if [[ ${context+.} ]]; then
		validate_non_range_commit_argument "${context}"
	else
		context=HEAD
	fi

	if [[ ${onto+.} ]]; then
		validate_non_range_commit_argument "${onto}"
	else
		onto=HEAD
	fi

	if [[ ${_VERBOSE} == true && _CALL_MSG_FD -ne 2 ]]; then
		exec {_CALL_MSG_FD}>&2 || die "Failed to copy FD 2."
	fi

	_ORIG_HEAD_REF=$(call git rev-parse --symbolic-full-name HEAD) || \
		die "Error occurred while trying to get current HEAD's reference"
	_ORIG_HEAD_COMMIT=$(call git rev-list --no-walk HEAD) && [[ ${_ORIG_HEAD_COMMIT} ]] || \
		die "Failed to get dereferenced object name of HEAD"

	_TOP_LEVEL_DIR=$(git rev-parse --show-toplevel) && [[ ${_TOP_LEVEL_DIR} ]] || \
		die "Failed to get top level directory."

	if [[ -e ${_TOP_LEVEL_DIR}/.git/MOVE_ORIG_HEAD ]] || \
			call git rev-parse --verify --quiet MOVE_ORIG_HEAD; then
		err "MOVE_ORIG_HEAD currently exists as a reference."
		err "This can happen if a move operation is currently ongoing, was interrupted or was cancelled."
		err "Please examine the reference to know where the original HEAD points at and revert changes manually."
		err "Run 'git update-ref -d MOVE_ORIG_HEAD --no-deref' to remove it after."
		return 1
	fi

	for __ in merge am rebase interactive_rebase cherry_pick revert; do
		"$__"_in_progress && die "Refusing to move anything while '${__//_/ }' is in progress."
	done

	git diff-index --quiet HEAD || \
		die "Please commit, stash, or discard changes before running git-move."

	call git rev-list ROOT &>/dev/null && die "ROOT can't be an actual existing reference."

	local context_ref context_commits=() context_head_commit=()

	context_ref=$(call git rev-parse --verify --symbolic-full-name "${context}") || \
		die "Error occurred while trying to get \"symbolic-full-name\" of ${context}"
	call git rev-list --reverse "${context}" | readarray -t context_commits || \
		die "Failed to enumerate all commits behind \"${context}\"."
	[[ ${context_commits+.} ]] || \
		die "No commit enumerated from \"${context}\""
	call git rev-list --no-walk "${context}" | readarray -t context_head_commit || \
		die "Failed to get commits of \"${context}\" using 'git rev-list --no-walk'"
	[[ ${context_head_commit+.} ]] || \
		die "No commit enumerated from \"${context}\" using 'git rev-list --no-walk'"
	[[ ${#context_head_commit[@]} -gt 1 ]] && \
		die "Multiple commits referred to by \"${context}\""
	[[ ${context_head_commit} != "${context_commits[-1]}" ]] && \
		die "Object enumerated through \"git rev-list --no-walk ${context@Q}\" unexpectedly differs from \"git rev-list --reverse ${context@Q}\": ${context_head_commit}, ${context_commits[-1]}"

	local -A context_commit_to_index=()

	for i in "${!context_commits[@]}"; do
		context_commit_to_index[${context_commits[i]}]=$i
	done

	context_commit_to_index[ROOT]=-1

	[[ -z ${onto+.} ]] && onto=${context_head_commit}

	local onto_commit=()

	if [[ ${onto} != ROOT ]]; then
		call git rev-list --no-walk "${onto}" | readarray -t onto_commit || \
			die "Failed to get commit object ID of \"${onto}\"."

		[[ ${onto_commit+.} ]] || die "\"${onto}\" did not expand to a commit."
		[[ ${#onto_commit[@]} -gt 1 ]] && die "\"${onto}\" expanded to multiple commits."
	fi

	local primary_picks=()
	local -A primary_pick_reg=()

	call git rev-list --no-walk=unsorted "${commit_args[@]}" | readarray -t primary_picks || \
		die "Failed to enumerate objects to move."

	[[ ${primary_picks+.} ]] || die "No source commits enumerated."

	for commit in "${primary_picks[@]}"; do
		[[ ${context_commit_to_index[${commit}]+.} ]] || {
			if [[ ${context} == "${context_head_commit}" ]]; then
				die "\"${commit}\" does not belong to \"${context}\"'s commit chain."
			else
				die "\"${commit}\" does not belong to \"${context} (${context_head_commit})\"'s commit chain."
			fi
		}

		[[ ${commit} == "${onto_commit}" ]] && die "\"${commit}\" and \"onto\" commit are the same."
		primary_pick_reg[${commit}]=.
	done

	local base_commit=ROOT base_commit_is_onto=false

	if [[ ${onto} == ROOT ]]; then
		base_commit_is_onto=true
	else
		local previous_commit=ROOT

		for i in "${!context_commits[@]}"; do
			commit=${context_commits[i]}

			if [[ ${commit} == "${onto_commit}" ]]; then
				base_commit=${commit}
				base_commit_is_onto=true
				break
			elif [[ ${primary_pick_reg[${commit}]+.} ]]; then
				base_commit=${previous_commit}
				break
			else
				previous_commit=${commit}
			fi
		done
	fi

	local base_picks=()

	if [[ ${base_commit_is_onto} == false ]]; then
		assert '${context_commit_to_index[${base_commit}]+.}'

		for (( i = ${context_commit_to_index[${base_commit}]} + 1, j = ${#context_commits[@]};
				i < j; ++i )); do
			commit=${context_commits[i]}

			if [[ ${primary_pick_reg[${commit}]+.} ]]; then
				assert '${commit} != "${onto_commit}"'
			else
				base_picks+=("${commit}")
				[[ ${commit} == "${onto_commit}" ]] && break
			fi
		done
	fi

	assert '${base_commit_is_onto} == true || ${base_picks+.}'

	local remaining_picks=()

	for (( i = ${context_commit_to_index[${onto_commit}]} + 1, j = ${#context_commits[@]};
			i < j; ++i )); do
		commit=${context_commits[i]}
		[[ ${primary_pick_reg[${commit}]+.} ]] || remaining_picks+=("${commit}")
	done

	[[ ${base_picks+.} || ${remaining_picks+.} ]] || die "Nothing to move."

	if [[ ${_ORIG_HEAD_REF} ]]; then
		call "${_DRY_RUN[@]}" git symbolic-ref MOVE_ORIG_HEAD "${_ORIG_HEAD_REF}" || \
			die "Failed to save original HEAD reference as MOVE_ORIG_HEAD"
	else
		call "${_DRY_RUN[@]}" git update-ref MOVE_ORIG_HEAD "${_ORIG_HEAD_COMMIT}" || \
			die "Failed to save original HEAD reference as MOVE_ORIG_HEAD"
	fi

	if [[ ${base_commit} == ROOT ]]; then
		_TEMPORARY_BRANCH_NAME=MOVE_${context_head_commit:0:10}
		_TEMPORARY_BRANCH_NAME=${_TEMPORARY_BRANCH_NAME^^}
		call "${_DRY_RUN[@]}" git switch --discard-changes --orphan "${_TEMPORARY_BRANCH_NAME}" --force || \
			abort "Failed to create a new root."
	else
		call "${_DRY_RUN[@]}" git checkout "${base_commit}" --detach || \
			abort "Failed to checkout \"${base_commit}\"."
	fi

	if [[ ${base_picks+.} ]]; then
		call "${_DRY_RUN[@]}" git cherry-pick "${base_picks[@]}" || \
			abort "Failure occurred while merging base commits."
	fi

	call "${_DRY_RUN[@]}" git cherry-pick "${primary_picks[@]}" || \
		die "Failure occurred while merging main commits."

	if [[ ${remaining_picks+.} ]]; then
		call "${_DRY_RUN[@]}" git cherry-pick "${remaining_picks[@]}" || \
			abort "Failure occurred while merging remaining commits."
	fi

	if [[ ${stay_detached} == false ]]; then
		if is_branch_ref "${context_ref}"; then
			call "${_DRY_RUN[@]}" git update-ref "${context_ref}" 'HEAD^{}' || \
				abort "Failed to save new HEAD reference to ${context_ref}"
		fi
	fi

	if [[ ${stay_detached} == false ]]; then
		if is_branch_ref "${_ORIG_HEAD_REF}"; then
			call "${_DRY_RUN[@]}" git switch "${_ORIG_HEAD_REF##*/}" || \
				die "Failed to switch back to ${_ORIG_HEAD_REF##*/}"
		else
			call "${_DRY_RUN[@]}" checkout "${_ORIG_HEAD_COMMIT}" || \
				die "Failed to switch back to ${_ORIG_HEAD_COMMIT}"
		fi
	elif [[ ${base_commit} == ROOT ]]; then
		call "${_DRY_RUN[@]}" git checkout --detach || \
			die "Failed to detach HEAD from temporary branch."
	fi

	remove_move_orig_head

	if [[ ${base_commit} == ROOT ]]; then
		call "${_DRY_RUN[@]}" git update-ref "${_TEMPORARY_BRANCH_NAME}" -d --no-deref || \
			die "Failed to remove temporary branch \"${_TEMPORARY_BRANCH_NAME}\"."
	fi
}

main "$@"
