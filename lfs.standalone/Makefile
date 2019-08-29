
MAPFILE		= ../app/mapfile
FLASH_BASE	= $(shell sed -rn 's/ *0x0*([0-9a-fA-F]+) *flash_region_base$$/0x\1/p' $(MAPFILE))
FLASH_OFFSET	= $(shell printf "0x%x" $$(($(FLASH_BASE) - 0x40200000)))

IMAGE_FILE	= LFS.$(FLASH_OFFSET).img

PORT		= /dev/ttyU0
BAUDRATE	= 74880
#BAUDRATE	= 115200
LOGFILE		= nodemcu.log

LUAC	       	= ../luac.cross.int
ESPTOOL	       	= esptool.py
ESPTOOL_ARGS   	= --chip esp8266 --port $(PORT) --baud 115200	# 115200 is the rate of the uploader, not of NodeMCU
WRITE_ARGS     	= --flash_size 4MB --flash_mode dout


.PHONY:		clean erase install_fw install_spiffs install_lfs

$(IMAGE_FILE):	*.lua
		$(LUAC) -o $@ -f -a $(FLASH_BASE) -s $^ 2>&1 | sed -r 's/^[^:]*: //'

clean:
		rm -f LFS.*.img

id:
		esptool.py chip_id
		esptool.py flash_id

erase:
		echo "==== Erasing flash"
		esptool.py erase_flash

install_fw:	0x*.bin
		echo "==== Installing firmware"
		esptool.py $(ESPTOOL_ARGS) write_flash $(WRITE_ARGS) \
			$$(for i in $^; do ADDR=$${i%.bin}; echo "$$ADDR" "$$i"; done)

install_spiffs:	0x*-*MB.img
		echo "==== Installing spiffs"
		esptool.py $(ESPT_ARGS) write_flash $(WRITE_ARGS) \
			$$(for i in $^; do ADDR=$${i%-*MB.img}; echo "$$ADDR" "$$i"; done)

install_lfs:	LFS.*.img
		echo "==== Installing LFS"
		esptool.py $(ESPT_ARGS) write_flash $(WRITE_ARGS) \
			$$(for i in $^; do ADDR=$${i#LFS.}; ADDR=$${ADDR%.img}; echo "$$ADDR" "$$i"; done)

log:
		cu -s $(BAUDRATE) -l $(PORT) | tee $(LOGFILE)
