# Installs commonly used programs

function install_i3() {
	# NOTE: For consistency all of the downloads directly reference a version. In the future I may attempt
	# a wildcard install to the latest stable.
	
	# install deps
	sudo apt-get install feh libxcb-icccm4-dev libxcb-util0-dev libxcb-keysyms1-dev \
		libxcb1-dev libyajl-dev libstartup-notification0-dev libxcb-randr0-dev \
		libxcb-xinerama0-dev  libxcb-randr0-dev libpango1.0-dev libxcursor-dev \
		libxcb-cursor-dev libev-dev  libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev \
		libgtk-3-dev libstartup-notification0-dev
	
	# download and install i3
	wget https://i3wm.org/downloads/i3-4.12.tar.bz2
	tar -vxjf i3-4.12.tar.bz2
	cd i3-4.12
	make
	sudo make install
	sudo cp i3.applications.desktop /usr/share/sessions # adds i3 to login menu
	cd ..
	echo "installed i3"
	
	# download and install i3blocks
	git clone git://github.com/vivien/i3blocks
	cd i3blocks
	make clean all
	sudo make install
	cd ..
	echo "installed i3blocks"
	
	# set up rofi
	wget https://github.com/DaveDavenport/rofi/releases/download/0.15.12/rofi-0.15.12.tar.gz -O rofi.tgz
	tar xvzf rofi.tgz
	cd rofi*
	./configure
	make
	sudo make install
	cd ..
	echo "installed rofi"
	
	echo "Done installing i3-wm, i3blocks and rofi."
}
	
function ubuntu_install () {
	# system basics
	sudo apt-get -y install cifs-utils filezilla gparted wicd nemo zsh tmux terminator fsarchiver

	# calibre
	sudo -v && wget -nv -O- https://raw.githubusercontent.com/kovidgoyal/calibre/master/setup/linux-installer.py | sudo python -c "import sys; main=lambda:sys.stderr.write('Download failed\n'); exec(sys.stdin.read()); main()"

	# add repos
	sudo add-apt-repository ppa:nathan-renniewaldock/flux -y
	sudo add-apt-repository ppa:n-muench/burg -y
	echo "deb http://dl.google.com/linux/deb/ stable  main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
	
	# update and install
	sudo apt-get update
	sudo apt-get -y install fluxgui burg burg-themes google-chrome-stable
}
