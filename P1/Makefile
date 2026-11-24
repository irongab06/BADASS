HOST_IMAGE = badass-host:1.0
ROUTER_IMAGE = badass-router:1.0
IMPORT_DIR = /tmp/badass-p1-import

all: host router

help:
	@echo "make         construit les deux images"
	@echo "make check   affiche les deux images et la ligne router bgp"
	@echo "make env     verifie les outils, Docker et les groupes de la machine"
	@echo "make load    charge les deux images depuis P1.gns3project, sans reseau"
	@echo "make clean   supprime les machines GNS3, les conteneurs et les deux images"
	@echo "make re      supprime puis reconstruit"

host:
	docker build -t $(HOST_IMAGE) -f _gacavali-1_host .

router:
	docker build -t $(ROUTER_IMAGE) -f _gacavali-2 .

check:
	docker image ls $(HOST_IMAGE)
	docker image ls $(ROUTER_IMAGE)
	docker run --rm $(ROUTER_IMAGE) grep "router bgp" /etc/frr/frr.conf

env:
	@sh check-env.sh

load:
	python3 -m zipfile -e P1.gns3project $(IMPORT_DIR)
	docker image load -i $(IMPORT_DIR)/docker-images-amd64.tar

clean:
	docker ps -aq --filter name=GNS3 | xargs -r docker rm -f
	docker ps -aq --filter ancestor=$(HOST_IMAGE) | xargs -r docker rm -f
	docker ps -aq --filter ancestor=$(ROUTER_IMAGE) | xargs -r docker rm -f
	-docker image rm $(HOST_IMAGE)
	-docker image rm $(ROUTER_IMAGE)

re: clean all

.PHONY: all help host router check env load clean re
