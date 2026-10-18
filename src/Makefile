# Out-of-tree build of the uas_arb module (patched Linux UAS driver with a device arbiter).
# Usage: make KDIR=/path/to/prepared/linux-<ver> [KBUILD_MODPOST_WARN=1]
KDIR ?= /lib/modules/$(shell uname -r)/build
obj-m := uas_arb.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
