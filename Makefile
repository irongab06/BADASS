# BADASS environment manager (Ubuntu only)
#
#   make check     Report what is installed and what is missing
#   make install   Install only what is missing, and remember what was added
#   make P1        Build the two Docker images of Part 1
#   make save      Save the two images to a compressed archive
#   make load      Restore the two images from that archive
#   make cleanP1   Stop and remove what "make P1" created
#   make clean     Remove the project's Docker containers and images
#   make fclean   Undo everything "make install" did (asks for confirmation)
#
# What fclean never touches:
#   - Anything that was on the machine before "make install"
#   - This repository, including P1, P2, P3 and your .gns3project exports
#
# How it stays safe: "make install" compares the machine before and after, and
# writes the differences to $(STATE_DIR). "make fclean" removes only that list.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help
# P1 must stay phony: a folder has that name, and make would call it up to date
.PHONY: help check install P1 save load cleanP1 clean fclean

# The real user, even when the Makefile is launched with sudo
TARGET_USER ?= $(or $(SUDO_USER),$(shell id -un))
USER_HOME ?= $(shell getent passwd $(TARGET_USER) | cut -d: -f6)
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

STATE_DIR ?= /var/lib/badass-env
CONFIRM ?= no

# Part 1: each image is built from its own folder, which holds a Dockerfile
LOGIN ?= ncardozo
P1_DIR ?= $(or $(wildcard P1),$(wildcard P1),P1)
P1_HOST ?= $(P1_DIR)/$(LOGIN)_host
P1_ROUTER ?= $(P1_DIR)/$(LOGIN)_router

# Archive used by "make save" and "make load"
IMAGES_ARCHIVE ?= $(P1_DIR)/badass-images.tar.gz

# Each entry is command:package. The command is what gets checked.
TOOLS ?= \
	docker:docker-ce \
	gns3server:gns3-server \
	gns3:gns3-gui \
	ubridge:ubridge \
	wireshark:wireshark \
	xterm:xterm \
	telnet:telnet \
	git:git

# Groups the user needs, when they exist on this machine
GROUPS_NEEDED := ubridge libvirt kvm wireshark docker

# Images removed by "make clean": the project's two images and their bases
IMAGE_RE ?= ^(badass-host|badass-router|alpine|quay\.io/frrouting/frr):

RESET	= \033[0m
BOLD	= \033[1m
GREEN	= \033[32m
CYAN	= \033[36m
YELLOW	= \033[33m
RED		= \033[31m
DIM		= \033[2m

MODULES_FILE := /etc/modules-load.d/badass-vxlan.conf
DOCKER_LIST := /etc/apt/sources.list.d/docker.list
DOCKER_KEY := /etc/apt/keyrings/docker.asc

define HELPERS
ok()   { printf '  $(GREEN)[ OK ]$(RESET) %s\n' "$$*"; }
warn() { printf '  $(YELLOW)[WARN]$(RESET) %s\n' "$$*"; }
bad()  { printf '  $(RED)[FAIL]$(RESET) %s\n' "$$*"; }
info() { printf '\n$(BOLD)$(CYAN)==> %s$(RESET)\n' "$$*"; }
die()  { printf '\n$(BOLD)$(RED)ERROR:$(RESET) %s\n' "$$*" >&2; exit 1; }
installed_packages() {
	dpkg-query -W -f='$${db:Status-Abbrev} $${Package}\n' \
		| awk '$$1 == "ii" { print $$2 }' | sort -u
}
apt_install() {
	$(SUDO) env DEBIAN_FRONTEND=noninteractive apt-get install -y "$$@"
}
state_add() { # file, line
	echo "$$2" | $(SUDO) tee -a "$(STATE_DIR)/$$1" > /dev/null
}
state_read() { # file (empty output when the file does not exist)
	$(SUDO) cat "$(STATE_DIR)/$$1" 2> /dev/null || true
}
tool_runs() { # GNS3 can be installed yet unable to start, so really run it
	case "$$1" in
		gns3|gns3server) "$$1" --version > /dev/null 2>&1 ;;
		*) command -v "$$1" > /dev/null 2>&1 ;;
	esac
}
gns3_problem() { # explains why an installed GNS3 does not start
	local version build system
	. /etc/os-release
	system=$${UBUNTU_CODENAME:-$${VERSION_CODENAME:-}}
	version=$$(dpkg-query -W -f='$${Version}' gns3-gui 2> /dev/null || true)
	build=$${version##*~}
	build=$${build%%[0-9]*}
	if [ -n "$$build" ] && [ "$$build" != "$$system" ]; then
		echo "its package was built for Ubuntu $$build, but this system is $$system. Point the GNS3 PPA at $$system and reinstall gns3-gui and gns3-server"
	else
		echo 'run gns3 in a terminal to see the error'
	fi
}
endef

help:
	printf '$(CYAN)make check$(RESET)    $(DIM)Report what is installed and what is missing$(RESET)\n'
	printf '$(CYAN)make install$(RESET)  $(DIM)Install only what is missing$(RESET)\n'
	printf '$(CYAN)make P1$(RESET)       $(DIM)Build the two Docker images of Part 1$(RESET)\n'
	printf '$(CYAN)make save$(RESET)     $(DIM)Save the two images to $(IMAGES_ARCHIVE)$(RESET)\n'
	printf '$(CYAN)make load$(RESET)     $(DIM)Restore the two images from $(IMAGES_ARCHIVE)$(RESET)\n'
	printf '$(CYAN)make cleanP1$(RESET)  $(DIM)Stop and remove what make P1 created$(RESET)\n'
	printf '$(CYAN)make clean$(RESET)    $(DIM)Remove the project containers and images$(RESET)\n'
	printf '$(CYAN)make fclean$(RESET)   $(DIM)Undo everything make install did (asks first)$(RESET)\n'

# ----------------------------------------------------------------------------
# 1. CHECK: changes nothing. Exits with an error when something required fails.
# ----------------------------------------------------------------------------
check:
	$(HELPERS)
	failed=0

	info 'Tools'
	for entry in $(TOOLS); do
		tool=$${entry%%:*}
		if ! command -v "$$tool" > /dev/null 2>&1; then
			bad "$$tool is missing (package $${entry##*:})"
			failed=1
		elif tool_runs "$$tool"; then
			ok "$$tool"
		else
			bad "$$tool is installed but does not start: $$(gns3_problem)"
			failed=1
		fi
	done

	info 'System'
	. /etc/os-release
	if [ "$${ID:-}" = ubuntu ]; then
		ok "$$PRETTY_NAME"
	else
		bad "$${PRETTY_NAME:-Unknown system}: this Makefile supports Ubuntu only"
		failed=1
	fi

	# The subject requires the whole project to run in a virtual machine
	virt=$$(systemd-detect-virt --vm 2> /dev/null || true)
	if [ -n "$$virt" ] && [ "$$virt" != none ]; then
		ok "Running in a virtual machine ($$virt)"
	else
		warn 'No virtual machine detected: the subject requires one'
	fi

	if command -v docker > /dev/null 2>&1; then
		if $(SUDO) docker info > /dev/null 2>&1; then
			ok 'Docker daemon is running'
		else
			bad 'Docker daemon is not reachable'
			failed=1
		fi
	fi

	if [ -d /sys/module/vxlan ]; then
		ok 'VXLAN kernel module is loaded'
	else
		warn 'VXLAN kernel module is not loaded (make install loads it)'
	fi

	info "Groups for $(TARGET_USER)"
	for group in $(GROUPS_NEEDED); do
		getent group "$$group" > /dev/null || continue
		# root already has every permission these groups grant
		if [ "$(TARGET_USER)" = root ]; then
			ok "$$group (not needed for root)"
		elif id -nG "$(TARGET_USER)" | grep -qw "$$group"; then
			ok "$$group"
			if ! id -nG | grep -qw "$$group" && [ "$$(id -u)" -ne 0 ]; then
				warn "$$group is not active yet: log out and back in"
			fi
		else
			bad "$(TARGET_USER) is not in $$group"
			failed=1
		fi
	done

	if [ "$$failed" -eq 0 ]; then
		printf '\n$(BOLD)$(GREEN)==> Environment is ready$(RESET)\n'
	else
		printf '\n$(BOLD)$(RED)==> Environment is incomplete: run make install$(RESET)\n'
	fi
	exit "$$failed"

# ----------------------------------------------------------------------------
# 2. INSTALL: safe to run several times. Installs only what is missing.
# ----------------------------------------------------------------------------
install:
	$(HELPERS)
	. /etc/os-release
	[ "$${ID:-}" = ubuntu ] || die 'This Makefile supports Ubuntu only'

	# Which tools are missing?
	missing=()
	need_gns3=no
	need_docker=no
	for entry in $(TOOLS); do
		command -v "$${entry%%:*}" > /dev/null 2>&1 && continue
		package=$${entry##*:}
		case "$$package" in
			gns3-*|ubridge) need_gns3=yes; missing+=("$$package") ;;
			docker-ce) need_docker=yes
				missing+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin) ;;
			*) missing+=("$$package") ;;
		esac
	done

	# Photograph the machine, and record the difference even if install fails
	$(SUDO) install -d -m 0755 "$(STATE_DIR)"
	tmp=$$(mktemp -d)
	installed_packages > "$$tmp/packages.before"
	getent group | cut -d: -f1 | sort -u > "$$tmp/groups.before"
	record() {
		installed_packages > "$$tmp/packages.after"
		getent group | cut -d: -f1 | sort -u > "$$tmp/groups.after"
		comm -13 "$$tmp/packages.before" "$$tmp/packages.after" \
			| $(SUDO) tee -a "$(STATE_DIR)/packages" > /dev/null
		comm -13 "$$tmp/groups.before" "$$tmp/groups.after" \
			| $(SUDO) tee -a "$(STATE_DIR)/groups-created" > /dev/null
		rm -rf "$$tmp"
	}
	trap record EXIT

	if [ "$${#missing[@]}" -gt 0 ]; then
		info "Installing: $${missing[*]}"
		$(SUDO) apt-get update -qq
		if [ "$$need_gns3" = yes ]; then
			apt_install software-properties-common
			if ! grep -rqs 'gns3/ppa' /etc/apt/sources.list.d; then
				$(SUDO) add-apt-repository -y ppa:gns3/ppa
				state_add repos ppa
			fi
		fi
		if [ "$$need_docker" = yes ]; then
			apt_install ca-certificates curl
			if ! grep -rqs 'download.docker.com' /etc/apt/sources.list.d; then
				$(SUDO) install -d -m 0755 /etc/apt/keyrings
				$(SUDO) curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$(DOCKER_KEY)"
				$(SUDO) chmod a+r "$(DOCKER_KEY)"
				echo "deb [arch=$$(dpkg --print-architecture) signed-by=$(DOCKER_KEY)]" \
					"https://download.docker.com/linux/ubuntu $${UBUNTU_CODENAME:-$$VERSION_CODENAME} stable" \
					| $(SUDO) tee "$(DOCKER_LIST)" > /dev/null
				state_add repos docker
			fi
		fi
		$(SUDO) apt-get update -qq
		# Answer "yes" in advance to the two questions asked during install
		printf '%s\n' \
			'ubridge ubridge/install-setuid boolean true' \
			'wireshark-common wireshark-common/install-setuid boolean true' \
			| $(SUDO) debconf-set-selections
		apt_install "$${missing[@]}"
	else
		info 'All tools are already installed'
	fi

	info 'Configuring the system'
	if [ -d /run/systemd/system ] && command -v docker > /dev/null 2>&1; then
		$(SUDO) systemctl enable --now docker > /dev/null 2>&1 \
			|| warn 'Could not start the Docker service'
	fi
	$(SUDO) modprobe vxlan 2> /dev/null || warn 'Could not load the VXLAN module'
	if [ ! -e "$(MODULES_FILE)" ]; then
		echo vxlan | $(SUDO) tee "$(MODULES_FILE)" > /dev/null
	fi
	for group in $(GROUPS_NEEDED); do
		[ "$(TARGET_USER)" = root ] && continue
		getent group "$$group" > /dev/null || continue
		id -nG "$(TARGET_USER)" | grep -qw "$$group" && continue
		$(SUDO) usermod -aG "$$group" "$(TARGET_USER)"
		state_add groups-joined "$$group"
		ok "Added $(TARGET_USER) to $$group"
	done

	$(MAKE) --no-print-directory check || true
	printf '\n$(YELLOW)If you were added to a group, log out and back in before using Docker or GNS3.$(RESET)\n'

# ----------------------------------------------------------------------------
# PART 1: builds the host and router images.
# ----------------------------------------------------------------------------
P1:
	$(HELPERS)
	command -v docker > /dev/null 2>&1 || die 'Docker is not installed: run make install'
	$(SUDO) docker info > /dev/null 2>&1 || die 'Docker daemon is not running'
	for pair in 'badass-host=$(P1_HOST)' 'badass-router=$(P1_ROUTER)'; do
		image=$${pair%%=*}
		folder=$${pair#*=}
		[ -f "$$folder/Dockerfile" ] || die "No Dockerfile found in $$folder"
		info "Building $$image from $$folder"
		$(SUDO) docker build -t "$$image" "$$folder"
	done
	info 'Images'
	$(SUDO) docker images | grep badass

	# GNS3 launch disabled for now: uncomment the lines below to restore it
	# # The images are built at this point, so GUI problems are only warnings
	# info 'Opening GNS3'
	# if ! command -v gns3 > /dev/null 2>&1; then
	# 	warn 'GNS3 is not installed: run make install'
	# elif ! tool_runs gns3; then
	# 	warn "GNS3 does not start: $$(gns3_problem)"
	# elif [ "$$(id -u)" -eq 0 ]; then
	# 	warn 'Run make P1 without sudo to open GNS3 as your own user'
	# elif [ -z "$${DISPLAY:-}$${WAYLAND_DISPLAY:-}" ]; then
	# 	warn 'No graphical session here: open a terminal from the desktop and run gns3'
	# elif pgrep -x gns3 > /dev/null 2>&1; then
	# 	ok 'GNS3 is already open'
	# else
	# 	setsid nohup gns3 > /dev/null 2>&1 < /dev/null &
	# 	gns3_pid=$$!
	# 	sleep 2
	# 	if kill -0 "$$gns3_pid" 2> /dev/null; then
	# 		ok 'GNS3 is starting'
	# 	else
	# 		warn 'GNS3 closed right after starting: run gns3 in a terminal to see the error'
	# 	fi
	# fi

# Writes both images into one compressed archive, as a backup for another machine.
save:
	$(HELPERS)
	command -v docker > /dev/null 2>&1 || die 'Docker is not installed: run make install'
	$(SUDO) docker info > /dev/null 2>&1 || die 'Docker daemon is not running'
	for image in badass-host badass-router; do
		$(SUDO) docker image inspect "$$image" > /dev/null 2>&1 \
			|| die "$$image does not exist: run make P1 first"
	done
	info 'Saving the images to $(IMAGES_ARCHIVE)'
	# Write to a temporary file first, so a failure never leaves a broken archive
	$(SUDO) docker save badass-host badass-router | gzip > '$(IMAGES_ARCHIVE).part'
	mv '$(IMAGES_ARCHIVE).part' '$(IMAGES_ARCHIVE)'
	size=$$(du -m '$(IMAGES_ARCHIVE)' | cut -f1)
	ok "Saved $(IMAGES_ARCHIVE) ($$size MB)"
	if [ "$$size" -ge 100 ]; then
		warn 'Over 100 MB: some Git servers refuse files this large'
	fi

# Restores both images from the archive, without rebuilding or downloading.
load:
	$(HELPERS)
	command -v docker > /dev/null 2>&1 || die 'Docker is not installed: run make install'
	$(SUDO) docker info > /dev/null 2>&1 || die 'Docker daemon is not running'
	[ -f '$(IMAGES_ARCHIVE)' ] || die 'No archive at $(IMAGES_ARCHIVE): run make save first'
	info 'Loading the images from $(IMAGES_ARCHIVE)'
	$(SUDO) docker load -i '$(IMAGES_ARCHIVE)'
	info 'Images'
	$(SUDO) docker images | grep badass

# Stops the containers, then removes them and the two images. Safe to run twice.
# Base images stay, so the next "make P1" is fast.
cleanP1:
	$(HELPERS)
	command -v docker > /dev/null 2>&1 || die 'Docker is not installed: run make install'
	$(SUDO) docker info > /dev/null 2>&1 || die 'Docker daemon is not running'
	info 'Cleaning Part 1'
	for image in badass-host badass-router; do
		if ! $(SUDO) docker image inspect "$$image" > /dev/null 2>&1; then
			ok "$$image is already gone"
			continue
		fi
		containers=$$($(SUDO) docker ps -aq --filter "ancestor=$$image")
		if [ -n "$$containers" ]; then
			$(SUDO) docker stop -t 5 $$containers > /dev/null
			$(SUDO) docker rm $$containers > /dev/null
			ok "Stopped and removed the $$image containers"
		fi
		$(SUDO) docker rmi "$$image" > /dev/null
		ok "Removed $$image"
	done

# ----------------------------------------------------------------------------
# 3a. CLEAN: removes the project's containers and images. Keeps the tools.
# ----------------------------------------------------------------------------
clean:
	$(HELPERS)
	if ! command -v docker > /dev/null 2>&1; then
		info 'Docker is not installed: no images to remove'
		exit 0
	fi
	if ! $(SUDO) docker info > /dev/null 2>&1; then
		warn 'Docker daemon is not running: images were not removed'
		exit 0
	fi
	info 'Removing project containers and images'
	images=$$($(SUDO) docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '$(IMAGE_RE)' || true)
	for image in $$images; do
		containers=$$($(SUDO) docker ps -aq --filter "ancestor=$$image")
		if [ -n "$$containers" ]; then
			$(SUDO) docker rm -f $$containers > /dev/null
		fi
		$(SUDO) docker rmi -f "$$image" > /dev/null
		ok "Removed $$image"
	done
	$(SUDO) docker builder prune -af > /dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# 3b. FCLEAN: undoes "make install", using only what it recorded.
# ----------------------------------------------------------------------------
fclean:
	$(HELPERS)
	case "$(USER_HOME)" in
		''|/) die 'Could not determine the home directory: stopping' ;;
	esac

	# Keep only recorded packages that are still installed
	tmp=$$(mktemp -d)
	trap 'rm -rf "$$tmp"' EXIT
	state_read packages | sort -u > "$$tmp/recorded"
	installed_packages > "$$tmp/installed"
	comm -12 "$$tmp/recorded" "$$tmp/installed" > "$$tmp/purge"
	has() { grep -qx "$$1" "$$tmp/recorded"; }

	# Stop now, before changing anything, if purging would remove other software
	if [ -s "$$tmp/purge" ]; then
		$(SUDO) apt-get -s purge $$(cat "$$tmp/purge") 2> /dev/null \
			| awk '$$1 == "Purg" || $$1 == "Remv" { sub(/:.*/, "", $$2); print $$2 }' \
			| sort -u > "$$tmp/simulated"
		comm -23 "$$tmp/simulated" "$$tmp/purge" > "$$tmp/extra"
		if [ -s "$$tmp/extra" ]; then
			cat "$$tmp/extra"
			die 'The packages above depend on these tools and would be removed too. Nothing was changed.'
		fi
	fi

	info 'This will permanently remove:'
	echo "  - The project's Docker containers and images"
	echo "  - $$(wc -l < "$$tmp/purge") packages installed by make install"
	if has docker-ce; then
		printf '$(RED)  - ALL Docker data: /var/lib/docker, /var/lib/containerd, /etc/docker$(RESET)\n'
	fi
	if has gns3-gui || has gns3-server; then
		printf '$(BOLD)$(RED)  - YOUR GNS3 WORK: %s/GNS3 and its settings$(RESET)\n' "$(USER_HOME)"
		printf '$(YELLOW)    Export your projects to P1, P2 and P3 first!$(RESET)\n'
	fi
	printf '$(DIM)  This repository is kept, including P1, P2 and P3.$(RESET)\n'

	if [ "$(CONFIRM)" != yes ]; then
		printf '\n$(BOLD)Type yes to continue:$(RESET) '
		read -r answer || answer=''
		[ "$$answer" = yes ] || { printf '$(YELLOW)Cancelled. Nothing was changed.$(RESET)\n'; exit 0; }
	fi

	$(MAKE) --no-print-directory clean

	if has docker-ce && [ -d /run/systemd/system ]; then
		info 'Stopping Docker'
		$(SUDO) systemctl stop docker.service docker.socket containerd.service 2> /dev/null || true
	fi

	for group in $$(state_read groups-joined | sort -u); do
		$(SUDO) gpasswd -d "$(TARGET_USER)" "$$group" > /dev/null 2>&1 || true
	done

	if [ -s "$$tmp/purge" ]; then
		info 'Removing packages'
		$(SUDO) env DEBIAN_FRONTEND=noninteractive apt-get purge -y $$(cat "$$tmp/purge")
	fi

	info 'Removing repositories and data'
	repos=$$(state_read repos)
	if grep -qx ppa <<< "$$repos"; then
		$(SUDO) rm -f /etc/apt/sources.list.d/gns3-ubuntu-ppa-* /etc/apt/trusted.gpg.d/gns3-ubuntu-ppa*
	fi
	if grep -qx docker <<< "$$repos"; then
		$(SUDO) rm -f "$(DOCKER_LIST)" "$(DOCKER_KEY)"
	fi
	if has docker-ce; then
		$(SUDO) rm -rf /var/lib/docker /var/lib/containerd /etc/docker "$(USER_HOME)/.docker"
	fi
	if has gns3-gui || has gns3-server; then
		$(SUDO) rm -rf "$(USER_HOME)/GNS3" "$(USER_HOME)/.config/GNS3" "$(USER_HOME)/.local/share/GNS3"
	fi
	if has wireshark; then
		$(SUDO) rm -rf "$(USER_HOME)/.config/wireshark"
	fi
	$(SUDO) rm -f "$(MODULES_FILE)"

	for group in $$(state_read groups-created | sort -u); do
		if getent group "$$group" > /dev/null; then
			$(SUDO) groupdel "$$group" 2> /dev/null || warn "Could not delete group $$group"
		fi
	done

	$(SUDO) apt-get update -qq || warn 'apt-get update failed'
	$(SUDO) rm -rf "$(STATE_DIR)"
	printf '\n$(BOLD)$(GREEN)==> Full cleanup finished.$(RESET) Log out and back in to refresh your groups.\n'
	