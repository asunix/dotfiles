#!/usr/bin/env bash

set -e
set -o pipefail

PLATFORM=$(/bin/uname)
export PLATFORM

export DEBIAN_FRONTEND=noninteractive

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

check_is_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root."
		exit
	fi
}

setup_sudo() {
	# add user to sudoers
	adduser "$TARGET_USER" sudo

	# add user to systemd groups
	# then you wont need sudo to view logs and shit
	gpasswd -a "$TARGET_USER" systemd-journal
	gpasswd -a "$TARGET_USER" systemd-network

	# create docker group
	sudo groupadd docker
	sudo gpasswd -a "$TARGET_USER" docker

	# add go path to secure path
	{ \
		echo -e "Defaults	secure_path=\"/usr/local/go/bin:/home/${TARGET_USER}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bcc/tools:/home/${TARGET_USER}/.cargo/bin\""; \
		echo -e 'Defaults	env_keep += "ftp_proxy http_proxy https_proxy no_proxy GOPATH EDITOR"'; \
		echo -e "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL"; \
		echo -e "${TARGET_USER} ALL=NOPASSWD: /sbin/ifconfig, /sbin/ifup, /sbin/ifdown, /sbin/ifquery"; \
	} >> /etc/sudoers

	# setup downloads folder as tmpfs
	# that way things are removed on reboot
	# i like things clean but you may not want this
	mkdir -p "/home/$TARGET_USER/Downloads"
	echo -e "\\n# tmpfs for downloads\\ntmpfs\\t/home/${TARGET_USER}/Downloads\\ttmpfs\\tnodev,nosuid,size=50G\\t0\\t0" >> /etc/fstab
}

install_homebrew() {
	if ! xcode-select -p 1>/dev/null; then
		echo -e "\\nxcode-select is not installed\\nPlease run the following command:\\n\\txcode-select install\\n"
		exit 1
	fi

	if command -v brew 1>/dev/null; then
		echo -e "\\nHomebrew is already installed\\n"
		exit 1
	fi

	if [[ -d $HOME/.homebrew ]]; then
		echo -e "\\n.homebrew already exists\\n"
		exit 1
	else
		mkdir "$HOME/.homebrew"
	fi

	if [[ -d $HOME/Library/Caches/Homebrew ]]; then
		echo -e "\\n$HOME/Library/Caches/Homebrew already exists\\n"
		exit 1
	fi

	# subshell
	(
	curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$HOME/.homebrew"
	)
}

install_scripts() {
	curl -sSL https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py  > /usr/local/bin/speedtest
	chmod +x /usr/local/bin/speedtest

	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/icdiff > /usr/local/bin/icdiff
	curl -sSL https://raw.githubusercontent.com/jeffkaufman/icdiff/master/git-icdiff > /usr/local/bin/git-icdiff
	chmod +x /usr/local/bin/icdiff
	chmod +x /usr/local/bin/git-icdiff
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GO_SRC=/usr/local/go

	# if we are passing the version
	if [[ -n "$1" ]]; then
		GO_VERSION=$1
	fi

	# purge old src
	if [[ -d "$GO_SRC" ]]; then
		sudo rm -rf "$GO_SRC"
		sudo rm -rf "$GOPATH"
	fi

	GO_VERSION=${GO_VERSION#go}

	# subshell
	(
	kernel=$(uname -s | tr '[:upper:]' '[:lower:]')
	curl -sSL "https://storage.googleapis.com/golang/go${GO_VERSION}.${kernel}-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
	local user="$USER"
	# rebuild stdlib for faster builds
	sudo chown -R "${user}" /usr/local/go/pkg
	CGO_ENABLED=0 go install -a -installsuffix cgo std
	)

	# get commandline tools
	(
	set -x
	set +e
	go get golang.org/x/lint/golint
	go get golang.org/x/tools/cmd/cover
	go get golang.org/x/tools/gopls
	go get golang.org/x/review/git-codereview
	go get golang.org/x/tools/cmd/goimports
	go get golang.org/x/tools/cmd/gorename
	go get golang.org/x/tools/cmd/guru

	go get github.com/genuinetools/amicontained
	go get github.com/genuinetools/apk-file
	go get github.com/genuinetools/audit
	go get github.com/genuinetools/bpfd
	go get github.com/genuinetools/bpfps
	go get github.com/genuinetools/certok
	go get github.com/genuinetools/netns
	go get github.com/genuinetools/pepper
	go get github.com/genuinetools/reg
	go get github.com/genuinetools/udict
	go get github.com/genuinetools/weather

	go get github.com/jessfraz/gmailfilters
	go get github.com/jessfraz/junk/sembump
	go get github.com/jessfraz/secping
	go get github.com/jessfraz/ship
	go get github.com/jessfraz/tdash

	go get github.com/axw/gocov/gocov
	go get honnef.co/go/tools/cmd/staticcheck

	# Tools for vimgo.
	go get github.com/jstemmer/gotags
	go get github.com/nsf/gocode
	go get github.com/rogpeppe/godef
	)

	# symlink weather binary for motd
	sudo ln -snf "${GOPATH}/bin/weather" /usr/local/bin/weather
}

get_dotfiles() {
	# create subshell
	(
	cd "$HOME"

	if [[ ! -d "${HOME}/dotfiles" ]]; then
		# install dotfiles from repo
		git clone https://github.com/asunix/dotfiles.git "${HOME}/dotfiles"
	fi

	cd "${HOME}/dotfiles"

	# set the correct origin
	git remote set-url origin https://github.com/asunix/dotfiles.git

	# installs all the things
	make

	cd "$HOME"
	)
}

install_tools() {
	# TODO: check if homebrew command exist if not exits try to install
	echo "Installing homebrew..."
	echo
	install_homebrew;

	echo "Installing golang..."
	echo
	install_golang;

	echo
	echo "Installing scripts..."
	echo
	install_scripts;
}

install_base() {
	if command -v brew 1>/dev/null; then
        	brew install --build-from-source go
        	brew install --build-from-source hugo
       		brew install --build-from-source source-to-image
        	brew install --build-from-source maven
        	brew install --build-from-source jmeter
        	brew install --build-from-source youtube-dl
        	brew install --build-from-source bash
        	brew install --build-from-source bash-completion@2
        	brew install --build-from-source openssl@1.1
        	brew install --build-from-source openssl
        	brew install --build-from-source autoconf
        	brew install --build-from-source automake
        	brew install --build-from-source pkg-config
        	brew install --build-from-source libtool
        	brew install --build-from-source nmap
        	brew install --build-from-source tree
        	brew install --build-from-source readline
        	brew install --build-from-source gettext
        	brew install --build-from-source ncurses
        	brew install --build-from-source libyaml
        	brew install --build-from-source libunistring
        	brew install --build-from-source libidn2
        	brew install --build-from-source wget
        	brew install --build-from-source ruby
        	brew install doxygen
        	brew install --build-from-source libevent
        	brew install --build-from-source tmux
        	brew install --build-from-source tmuxinator-completion
        	brew remove doxygen
	else
		echo -e "\\nHomebrew is not installed\\n"
		exit 1
	fi
}

setup_sources_min_debian() {
	apt update || true
	apt install -y \
		apt-transport-https \
		ca-certificates \
		curl \
		dirmngr \
		gnupg2 \
		lsb-release \
		--no-install-recommends

	# hack for latest git (don't judge)
	cat <<-EOF > /etc/apt/sources.list.d/git-core.list
	deb http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main
	deb-src http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main
	EOF

	# add the git-core ppa gpg key
	apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24

	# turn off translations, speed up apt update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations
}

setup_sources_debian() {
	setup_sources_min_debian

	cat <<-EOF > /etc/apt/sources.list
	deb http://deb.debian.org/debian/ sid main contrib non-free
	deb-src http://deb.debian.org/debian/ sid main contrib non-free
	EOF
}

base_min_debian() {
	apt update || true
	apt -y upgrade

	apt install -y \
		adduser \
		automake \
		bash-completion \
		bc \
		bzip2 \
		ca-certificates \
		coreutils \
		curl \
		dnsutils \
		file \
		findutils \
		gcc \
		git \
		gnupg \
		gnupg2 \
		grep \
		gzip \
		hostname \
		indent \
		iptables \
		jq \
		less \
		libc6-dev \
		locales \
		lsof \
		make \
		mount \
		net-tools \
		policykit-1 \
		silversearcher-ag \
		ssh \
		strace \
		sudo \
		tar \
		tree \
		tzdata \
		unzip \
		vim \
		xz-utils \
		zip \
		--no-install-recommends

	apt autoremove -y
	apt autoclean -y
	apt clean -y

	install_scripts
}

base_debian() {
	base_min_debian

	apt update || true
	apt -y upgrade

	apt install -y \
		apparmor \
		bridge-utils \
		cgroupfs-mount \
		fwupd \
		fwupdate \
		gnupg-agent \
		google-cloud-sdk \
		iwd \
		libapparmor-dev \
		libimobiledevice6 \
		libltdl-dev \
		libpam-systemd \
		libpcsclite-dev \
		libseccomp-dev \
		pcscd \
		pinentry-curses \
		scdaemon \
		systemd \
		powertop \
		--no-install-recommends

	setup_sudo

	apt autoremove -y
	apt autoclean -y
	apt clean -y
}

usage() {
	echo -e "install.sh\\n\\tThis script installs my basic setup for a mac or linux laptop\\n"
	echo "Usage:"
	echo "  base                       - setup sources & install base pkgs"
	echo "  dotfiles                   - get dotfiles"
	echo "  golang                     - install golang and packages"
	echo "  scripts                    - install scripts"
	echo "  tools                      - install golang and scripts"
	echo "  homebrew                   - install homebrew package manager"
}

main() {
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "base" ]]; then
		case $PLATFORM in
		Linux)
			check_is_sudo
			get_user

			setup_sources_debian
			
			base_debian
			;;
		Darwin)
        	install_base
			;;
		*)
			echo ""
			;;
		esac
	elif [[ $cmd == "dotfiles" ]]; then
		get_user
		get_dotfiles
	elif [[ $cmd == "golang" ]]; then
		install_golang "$2"
	elif [[ $cmd == "scripts" ]]; then
		check_is_sudo

		install_scripts
	elif [[ $cmd == "tools" ]]; then
		install_tools
	elif [[ $cmd == "homebrew" ]]; then
		install_homebrew
	else
		usage
	fi
}

main "$@"
