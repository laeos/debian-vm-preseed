
NAME   ?= default
DOMAIN ?= avalon.fnordsoft.com
IMAGES ?= /home/libvirt/images
PKG    ?= nullmailer
FROM   ?= default

export NAME DOMAIN IMAGES

.PHONY: default
default:
	@echo "you can preseed, udebpkgs, clean, build NAME=, extract PKG=, destroy NAME=, clone FROM= TO="


.PHONY: build
build: $(IMAGES)/$(NAME).qcow

$(IMAGES)/$(NAME).qcow:
	$(MAKE) preseed NAME=$(NAME)
	sudo virt-install \
		--connect qemu:///system \
		--virt-type kvm \
		--name $(NAME) \
		--ram 2048 \
		--vcpus 2 \
		--cpu host \
		--os-variant debian11 \
		--disk path=/home/libvirt/images/$(NAME).qcow2,size=16 \
		--memballoon virtio \
		--network bridge=br1,model=virtio \
		--tpm default \
		--graphics none  \
		--console pty,target_type=serial \
		--extra-args 'console=ttyS0,115200n8 serial auto=true hostname="$(NAME)" domain="$(DOMAIN)"' \
		--location http://ftp.us.debian.org/debian/dists/stable/main/installer-amd64/ \
		--initrd-inject=tmp/preseed.cfg \
		--initrd-inject=tmp/postinst.sh \
		--boot menu=on,useserial=on \
		--serial pty \
		--rng /dev/random \
		--controller usb,model=none \
		--filesystem /shared,shared


.PHONY: preseed
preseed:
	mkdir -p tmp
	./yaml-data | mustache - preseed.cfg.mustache > tmp/preseed.cfg
	./yaml-data | mustache - postinst.sh.mustache > tmp/postinst.sh
	diff -u1 preseed.cfg.mustache tmp/preseed.cfg || exit 0
	diff -u1 postinst.sh.mustache tmp/postinst.sh || exit 0
	debconf-set-selections  -c tmp/preseed.cfg


.PHONY: udebpkgs
udebpkgs:
	mkdir -p tmp
	if [ -r udebpkgs ]; then mv udebpkgs tmp/udebpkgs.old ; fi
	apt-cache dumpavail | grep ^Package: | cut -d" " -f2 > udebpkgs
	if [ -r tmp/udebpkgs.old ]; then diff -u tmp/udebpkgs.old udebpkgs; fi


.PHONY: clean
clean:
	-rm -rf tmp udebpkgs


.PHONY: destroy
destroy:
	-sudo virsh destroy $(NAME)
	-sudo virsh undefine $(NAME)
	-sudo rm $(IMAGES)/$(NAME).qcow2



.PHONY: extract tmp/$(PKG).template
extract: tmp/$(PKG).template

tmp/$(PKG).template:
	mkdir -p tmp
	(cd tmp && apt download $(PKG))
	(cd tmp && apt-extracttemplates -t . $(PKG)*.deb)
	(cd tmp && rm $(PKG)*.config.*)
	./extract-questions tmp/$(PKG)*.template.* > tmp/$(PKG).template


.PHONY: clone
clone:
ifeq ($(strip $(TO)),)
	@echo "make clone FROM=$(FROM) TO="
else
	sudo virt-clone --original $(FROM) --name $(TO) --file=$(IMAGES)/$(TO).qcow2
	sudo virt-sysprep -d $(TO) --hostname $(TO) --enable net-hostname,net-hwaddr,kerberos-data,customize,dhcp-client-state,logfiles,machine-id
endif

