# SPDX-License-Identifier: MIT

.PHONY: all build test clean

all: build

build:
	./build.sh

test: build
	zsh -n build.sh
	zsh -n build_app.sh
	python3 -m py_compile lenovo_40an_vmm5322_split.py
	plutil -lint dist/StretchTheMac.app/Contents/Info.plist
	./dist/StretchTheMac.app/Contents/MacOS/StretchTheMac --selftest-snap

clean:
	swift package clean
	rm -rf .build dist
