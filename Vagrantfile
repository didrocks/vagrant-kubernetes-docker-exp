# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|

  config.vm.box = "http://sourceforge.net/projects/opensusevagrant/files/13.2/opensuse-13.2-64.box/download"
  config.vm.provision :shell, path: "vagrantsetup.sh"
  config.vm.network "forwarded_port", guest: 30001, host: 8000

end
