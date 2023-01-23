#!/usr/bin/env bash

set -e
set -o pipefail

PLATFORM=$(/usr/bin/uname)
export PLATFORM

check_is_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root."
		exit
	fi
}

# Choose a user account to use for this installation
get_user() {
	if [[ -z "${TARGET_USER-}" ]]; then
		mapfile -t options < <(find /home/* -maxdepth 0 -printf "%f\\n" -type d)
		# if there is only one option just use that user
		if [ "${#options[@]}" -eq "1" ]; then
			readonly TARGET_USER="${options[0]}"
			echo "Using user account: ${TARGET_USER}"
			return
		fi

		# iterate through the user options and print them
		PS3='command -v user account should be used? '

		select opt in "${options[@]}"; do
			readonly TARGET_USER=$opt
			break
		done
	fi
}

setup_sudo() {
	# add user to sudoers
	adduser "$TARGET_USER" sudo

	# add user to systemd groups
	# then you wont need sudo to view logs and shit
	gpasswd -a "$TARGET_USER" systemd-journal
	gpasswd -a "$TARGET_USER" systemd-network

	# add go path to secure path
	{ \
		echo -e "Defaults       secure_path=\"/home/linuxbrew/.linuxbrew/bin:/home/${TARGET_USER}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bcc/tools:/home/${TARGET_USER}/.cargo/bin\""; \
		echo -e 'Defaults       env_keep += "ftp_proxy http_proxy https_proxy no_proxy GOPATH EDITOR"'; \
		echo -e "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL"; \
		echo -e "${TARGET_USER} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery"; \
	} > /etc/sudoers.d/"${TARGET_USER}"
	chmod o-r /etc/sudoers.d/"${TARGET_USER}"

	# setup downloads folder as tmpfs
	# that way things are removed on reboot
	# i like things clean but you may not want this
	mkdir -p "/home/$TARGET_USER/Downloads"
	echo -e "\\n# tmpfs for downloads\\ntmpfs\\t/home/${TARGET_USER}/Downloads\\ttmpfs\\tnodev,nosuid,size=50G\\t0\\t0" >> /etc/fstab
}

install_homebrew() {

	case $PLATFORM in
	Linux)
		if command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is already installed\\n"
			exit 1
		fi

		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		cat <<-EOF >> ~/.profile
		# Set PATH, MANPATH, etc., for Homebrew.
		eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
		EOF
		# TO BE CHANGED
		# shellcheck source=/dev/null
		source "$HOME"/.profile

		brew install go
		brew install helm
		brew install kubernetes-cli
		brew install jq
		brew install ipcalc
		brew install hugo
		brew install kubectx
		brew install tree
		brew install shellcheck
		echo -e "\\nHomebrew installed and configured. To use it, logout and login again or run the following command:\\n"
		echo -e "source ~/.profile\\n"
		;;
	Darwin)
		if ! xcode-select -p 1>/dev/null; then
			echo -e "\\nxcode-select is not installed\\nPlease run the following command:\\n\\txcode-select install\\n"
			exit 1
		fi

		if command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is already installed\\n"
			exit 1
		fi

		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

		brew install go
		brew install helm
		brew install kubernetes-cli
		brew install jq
		brew install ipcalc
		brew install hugo
		brew install kubectx
		brew install tree
		brew install tmux
		brew install tmuxinator
		brew install shellcheck
		brew install bash
		brew install bash-completion
		brew install --cask alacritty
		;;
	*)
		echo "Unknow $PLATFORM, do nothing"
		;;
	esac
}

install_base() {
	case $PLATFORM in
	Linux)
		sudo apt update || true
		sudo apt -y upgrade

		sudo apt install -y \
			ca-certificates \
			coreutils \
			curl \
			dnsutils \
			net-tools \
			sudo \
			apt-transport-https \
			dirmngr \
			lsb-release \
			ifupdown \
			git \
			build-essential \
			fonts-powerline \
			cpu-checker \
			--no-install-recommends

		sudo apt autoremove -y
		sudo apt autoclean -y
		sudo apt clean -y
		;;
	Darwin)
		;;
	esac
}

install_vagrant() {
	case $PLATFORM in
	Linux)
		wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
		echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
		sudo apt update || true
		sudo apt install -y vagrant
		sudo apt autoremove -y
		sudo apt autoclean -y
		sudo apt clean -y
		;;
	Darwin)
		if ! command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is not installed\\n"
			exit 1
		fi
		brew install hashicorp/tap/hashicorp-vagrant
		;;
	esac
}

get_dotfiles() {
	case $PLATFORM in
	Linux)
		if ! command -v git 1>/dev/null; then
			echo -e "\\ngit is not installed\\n"
			exit 1
		fi
		if ! command -v make 1>/dev/null; then
			echo -e "\\nmake is not installed\\n"
			exit 1
		fi
		;;
	Darwin)
		if ! xcode-select -p 1>/dev/null; then
			echo -e "\\nxcode-select is not installed\\nPlease run the following command:\\n\\txcode-select install\\n"
			exit 1
		fi
		git clone https://github.com/powerline/fonts.git --depth=1
		cd fonts
		./install.sh
		cd ..
		rm -rf fonts
		;;
	esac
	# create subshell
	(
	cd "$HOME"

	if [[ ! -d "${HOME}/dotfiles" ]]; then
		# install dotfiles from repo
		git clone https://github.com/asunix/dotfiles.git "${HOME}/dotfiles"
	fi

	cd "${HOME}/dotfiles"

	# set the correct origin
	git remote set-url origin git@github.com:asunix/dotfiles.git

	# installs all the things
	make
	)
}

use_yubikey() {
	case $PLATFORM in
	Linux)
		sudo apt update || true
		sudo apt install -y \
			wget \
			gnupg2 \
			gnupg-agent \
			dirmngr \
			cryptsetup \
			scdaemon \
			pcscd \
			pcsc-tools \
			secure-delete \
			libu2f-udev \
			hopenpgp-tools \
			yubikey-personalization \
			python3-pip \
			python3-pyscard
		sudo apt autoremove -y
		sudo apt autoclean -y
		sudo apt clean -y
		pip3 install PyOpenSSL
		pip3 install yubikey-manager
		sudo systemctl enable --now pcscd
		;;
	Darwin)
		if ! command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is not installed\\n"
			exit 1
		fi
		brew install gnupg yubikey-personalization hopenpgp-tools ykman pinentry-mac wget pidof
		;;
	esac
}

usage() {
	echo -e "install.sh\\n\\tThis script installs my basic setup for a mac or linux virt server\\n"
	echo "Usage:"
	echo "  sudo                       - configure sudo for linux server"
	echo "  homebrew                   - install homebrew package manager"
	echo "  vagrant                    - install Hashicorp Vagrant"
	echo "  yubikey                    - install yubikey tools and gnupg"
	echo "  qemu                       - install qemu on Mac and qemu libvirt on Linux"
	echo "  dotfiles                   - install dot files"
	echo "  scripts                    - install scripts"
}

main() {
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "sudo" ]]; then
		check_is_sudo
		install_base

		case $PLATFORM in
		Linux)
			get_user
			setup_sudo
			;;
		Darwin)
			echo "Is not necessary for my mac os, do nothing"
			;;
		esac
	elif [[ $cmd == "homebrew" ]]; then
		install_base
		install_homebrew
	elif [[ $cmd == "vagrant" ]]; then
		install_vagrant
	elif [[ $cmd == "yubikey" ]]; then
		use_yubikey
	elif [[ $cmd == "qemu" ]]; then
		echo "Not implemented"
	elif [[ $cmd == "dotfiles" ]]; then
		get_dotfiles
	elif [[ $cmd == "scripts" ]]; then
		echo "Not implemented"
	else
		usage
	fi
}

main "$@"
