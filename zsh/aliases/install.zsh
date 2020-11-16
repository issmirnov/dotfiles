#!/usr/bin/env zsh
#
# Insprired by https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/extract
alias i=install

install() {
	local target

	if (( $# == 0 )); then
		cat <<-'EOF' >&2
			Usage: install [-option] [file.deb apt_pkg pkg.snap]

			Options:
			    -r, --remove    Remove target after installation.
				--system-bin    Place binary into /usr/local/bin/
		EOF
	fi

	remove_archive=1
	if [[ "$1" == "-r" ]] || [[ "$1" == "--remove" ]]; then
		remove_archive=0
		shift
	fi

	system_bin=1
	if [[ "$1" == "--system-bin" ]]; then
		system_bin=0
		shift
	fi


	while (( $# > 0 )); do
		if [[ ! -f "$1" ]]; then
			echo "install: '$1' is not a valid file" >&2
			shift
			continue
		fi

		success=0
		case "${1:l}" in
			(*.deb) sudo dpkg -i "$1" ;;
			(*.snap) snap install --dangerous "$1" ;;
			(*)
				echo "install: '$1' does not match any file patterns" >&2
				success=1
			;;
		esac

		# check if this is a binary, in which case we can put it into user bin
		# TODO add sanity checking for the wrong architecture. might be able to use `file` + `uname`
		#kernel_arch=$(uname -p) # -mpi
		#


		(( success = $success > 0 ? $success : $? ))
		(( $success == 0 )) && (( $remove_archive == 0 )) && rm "$1"
		shift
	done
}
