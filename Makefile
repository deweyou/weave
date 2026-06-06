.PHONY: install desktop-dev desktop-build dev test check

install:
	vp install

desktop-dev:
	vp run desktop-dev

desktop-build:
	vp run desktop-build

dev:
	$(MAKE) desktop-dev

test:
	vp run check

check:
	vp run check
