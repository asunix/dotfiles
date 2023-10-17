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

		# shellcheck source=/dev/null
		source "$HOME"/.profile

		export HOMEBREW_NO_INSTALL_CLEANUP=1
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

		export HOMEBREW_NO_INSTALL_CLEANUP=1
		BREW_PREFIX=$(brew --prefix)

		brew install coreutils
		brew install moreutils
		brew install findutils
		brew install gnu-getopt
		brew install make
		brew install gnu-sed
		brew install wget
		brew install grep
		brew install screen
		brew install openssh
		
		# Install font tools.
		brew tap bramstein/webfonttools
		brew install sfnt2woff
		brew install sfnt2woff-zopfli
		brew install woff2

		brew install nmap
		brew install socat
		brew install git
		brew install git-lfs
		brew install ssh-copy-id

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
		brew install bash-completion@2
		brew install docker
		brew install podman

		if [[ ! -d "${HOME}/.tmux" ]]; then
			git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
		fi

		brew install --cask alacritty
		brew install --cask google-chrome
		brew install --cask microsoft-teams
		brew install --cask skype
		brew install --cask whatsapp
		brew install --cask 1password
		brew install --cask alfred
		brew install --cask iterm2
		brew install --cask appcleaner
		brew install --cask wireshark
		brew install --cask utm
		brew install --cask tower
		brew install --cask send-to-kindle
		brew install --cask kindle
		brew install --cask visual-studio-code
		brew install --cask kaleidoscope
		brew install --cask drawio
		brew install --cask keycastr
		brew install --cask marked
		brew install --cask telegram-desktop
		brew install --cask signal
		brew install --cask spotify
		brew install --cask xquartz
		brew install --cask istat-menus
		brew install --cask bartender
		brew install --cask firefox
		brew install --cask vmware-horizon-client
		brew install --cask intellij-idea

		# Switch to using brew-installed bash as default shell
		if ! grep -F -q "${BREW_PREFIX}/bin/bash" /etc/shells; then
  			echo "${BREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells;
  			chsh -s "${BREW_PREFIX}/bin/bash";
		fi;
		
		# Remove outdated versions from the cellar.
		brew cleanup
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
			vim \
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
		export HOMEBREW_NO_INSTALL_CLEANUP=1
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
	if [[ ! -d "$HOME/.gnupg" ]]; then
		echo -e "\\n.gnupg directory is not configured, please install dotfiles before configure yubikey"
		exit 1
	fi
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
		ln -sfn "$HOME"/.gnupg/gpg-agent.conf.Linux "$HOME"/.gnupg/gpg-agent.conf
		;;
	Darwin)
		if ! command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is not installed\\n"
			exit 1
		fi
		export HOMEBREW_NO_INSTALL_CLEANUP=1
		brew install gnupg yubikey-personalization hopenpgp-tools ykman pinentry-mac wget pidof
		brew cleanup
                if [[ $(uname -m) == 'arm64' ]]; then
		   ln -sfn "$HOME"/.gnupg/gpg-agent.conf.Darwin.M1 "$HOME"/.gnupg/gpg-agent.conf
                else
		   ln -sfn "$HOME"/.gnupg/gpg-agent.conf.Darwin.Intel "$HOME"/.gnupg/gpg-agent.conf
                fi
		;;
	esac
}

cleanupall() {
	case $PLATFORM in
	Linux)
		echo -e "\\nNothing to do for Linux\\n"
		;;
	Darwin)
		echo -e "\\nRemove all symbolic links"
		find "$HOME"/dotfiles -type f -name ".*" -not -name ".gitignore" -not -name ".git" -not -name ".config" -not -name ".github" -not -name ".*.swp" -not -name ".gnupg" | while read -r file
		do
			f=$(basename "$file")
			rm -f "$HOME"/"$f"
		done
		rm -f "$HOME"/.profile
		find "$HOME"/dotfiles/bin -type f -not -name "*-backlight" -not -name ".*.swp" | while read -r file
		do
			f=$(basename "$file")
			sudo rm -f /usr/local/bin/"$f"
		done
		echo -e "\\nRemove gnupg config directory"
		rm -rf "$HOME"/.gnupg
		brew uninstall --cask --force alacritty
		brew uninstall --cask --force google-chrome
		brew uninstall --cask --force microsoft-teams
		brew uninstall --cask --force skype
		brew uninstall --cask --force whatsapp
		brew uninstall --cask --force 1password
		brew uninstall --cask --force alfred
		brew uninstall --cask --force iterm2
		brew uninstall --cask --force appcleaner
		brew uninstall --cask --force wireshark
		brew uninstall --cask --force utm
		brew uninstall --cask --force tower
		brew uninstall --cask --force send-to-kindle
		brew uninstall --cask --force kindle
		brew uninstall --cask --force visual-studio-code
		brew uninstall --cask --force kaleidoscope
		brew uninstall --cask --force drawio
		brew uninstall --cask --force keycastr
		brew uninstall --cask --force marked
		brew uninstall --cask --force telegram-desktop
		brew uninstall --cask --force signal
		brew uninstall --cask --force spotify
		brew uninstall --cask --force xquartz
		brew uninstall --cask --force istat-menus
		brew uninstall --cask --force bartender
		brew uninstall --cask --force firefox
		brew uninstall --cask --force vmware-horizon-client
		brew uninstall --cask --force intellij-idea

		BREW_PREFIX=$(brew --prefix)
		if grep -F -q "${BREW_PREFIX}/bin/bash" /etc/shells; then
  			chsh -s "/bin/zsh";
			echo -e "\\n--------------------------------------------------------------------------------"
			echo -e "\\nRemember to delete custom bash configuration from /etc/shells"
			echo -e "\\nsudo vi /etc/shells"
			echo -e "\\n--------------------------------------------------------------------------------"
		fi;
		echo -e "\\n--------------------------------------------------------------------------------"
		echo -e "\\nRemember to delete dotfiles directory, can you do it with the following command:"
		echo -e "\\nrm -rf $HOME/dotfiles"
		echo -e "\\n--------------------------------------------------------------------------------"
		if [[ -d "${HOME}/.tmux" ]]; then
			rm -rf "${HOME}/.tmux"
		fi
		if [[ -d "${HOME}/.vscode" ]]; then
			rm -rf "${HOME}/.vscode"
		fi
		if [[ -f "/usr/local/bin/speedtest" ]]; then
			rm -f "/usr/local/bin/speedtest"
		fi
		if [[ -f "$HOME/.gitignore" ]]; then
			rm -f "$HOME/.gitignore"
		fi
		if [[ -f "/usr/local/bin/icdiff" ]]; then
			rm -f "/usr/local/bin/icdiff"
		fi
		if [[ -f "/usr/local/bin/git-icdiff" ]]; then
			rm -f "/usr/local/bin/git-icdiff"
		fi
		if [[ -f "/usr/local/bin/lolcat" ]]; then
			rm -f "/usr/local/bin/lolcat"
		fi
		# create subshell
		(
		echo -e "\\nRemove HomeBrew"
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
		)
		;;
	esac
}

qemu() {
	case $PLATFORM in
	Linux)
		echo -e "\\nNothing to do for Linux\\n"
		;;
	Darwin)
		if ! command -v brew 1>/dev/null; then
			echo -e "\\nHomebrew is not installed\\n"
			exit 1
		fi
		export HOMEBREW_NO_INSTALL_CLEANUP=1
		brew install qemu
		brew install lima
		brew cleanup
		;;
	esac
}

install_scripts() {
	curl -sSL https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py  > /usr/local/bin/speedtest
	chmod +x /usr/local/bin/speedtest
	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/icdiff > /usr/local/bin/icdiff
	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/git-icdiff > /usr/local/bin/git-icdiff
	chmod +x /usr/local/bin/icdiff
	chmod +x /usr/local/bin/git-icdiff
	curl -sSL https://raw.githubusercontent.com/tehmaze/lolcat/master/lolcat > /usr/local/bin/lolcat
	chmod +x /usr/local/bin/lolcat
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
		qemu
	elif [[ $cmd == "dotfiles" ]]; then
		get_dotfiles
	elif [[ $cmd == "scripts" ]]; then
		install_scripts
	elif [[ $cmd == "cleanupall" ]]; then
		cleanupall
	else
		usage
	fi
}

main "$@"
