HOST_IMAGE = badass-host:1.0
ROUTER_IMAGE = badass-router:1.0

all: host router

host:
	docker build -t $(HOST_IMAGE) -f _gacavali-1_host .

router:
	docker build -t $(ROUTER_IMAGE) -f _gacavali-2 .

check:
	docker image ls $(HOST_IMAGE)
	docker image ls $(ROUTER_IMAGE)
	docker run --rm $(ROUTER_IMAGE) grep "router bgp" /etc/frr/frr.conf

clean:
	-docker image rm $(HOST_IMAGE)
	-docker image rm $(ROUTER_IMAGE)

re: clean all

.PHONY: all host router check clean re
