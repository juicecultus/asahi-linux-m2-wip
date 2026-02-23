obj-m := phy-apple-atc.o
phy-apple-atc-y := atc.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install:
	xz -f phy-apple-atc.ko
	sudo cp phy-apple-atc.ko.xz /lib/modules/$(shell uname -r)/kernel/drivers/phy/apple/phy-apple-atc.ko.xz
	sudo depmod -a
