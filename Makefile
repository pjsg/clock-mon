

lua = $(wildcard *.lua)

%.uploaded: %.lua
	@if ! cmp -s $< $@; then tftp -m binary 192.168.1.114 -c put $<; echo Uploaded $<;fi
	@cp $< $@


all: $(lua:.lua=.uploaded)

