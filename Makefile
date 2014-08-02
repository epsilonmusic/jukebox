APPNAME    = Epsilon
PKGNAME    = epsilon-jukebox

APPCONTENT = app package.json LICENSE
APPFILES   = $(shell find app -type f -print) package.json LICENSE

NWVERSION  = v0.10.0
NWOSX      = node-webkit-${NWVERSION}-osx-ia32

PREFIX     = /usr/local
DESTDIR    =

ifneq (${OS},Windows_NT)
OS = $(shell uname -s)
endif

LINUX_ICON_SIZES = 32x32 48x48 384x384

# Dependencies

cache/${NWOSX}: | cache
	cd cache && \
	curl -o ${NWOSX}.zip \
		"http://dl.node-webkit.org/${NWVERSION}/${NWOSX}.zip" && \
	unzip ${NWOSX}.zip

cache:
	mkdir -p $@

node_modules: package.json
	npm install

# Final results

all: build/osx/${APPNAME}.app build/win/${APPNAME}

build/osx/${APPNAME}.app: node_modules ${APPFILES} \
		support/osx/Info.plist support/osx/${APPNAME}.icns \
		| cache/${NWOSX} build/osx
	
	rm -rf build/osx/${APPNAME}.app
	cp -r cache/${NWOSX}/node-webkit.app build/osx/${APPNAME}.app

	cp support/osx/Info.plist build/osx/${APPNAME}.app/Contents/
	cp support/osx/${APPNAME}.icns build/osx/${APPNAME}.app/Contents/Resources/

	mkdir build/osx/${APPNAME}.app/Contents/Resources/app.nw
	cp -r node_modules build/osx/${APPNAME}.app/Contents/Resources/app.nw/
	cp -r ${APPCONTENT} build/osx/${APPNAME}.app/Contents/Resources/app.nw/

build/win/${APPNAME}: node_modules ${APPFILES} | build/win

build build/osx build/win:
	mkdir -p $@

# Installation

install: install-${OS}

install-Linux: node_modules ${APPFILES} support/linux/${PKGNAME}.desktop
	install -d "${DESTDIR}/${PREFIX}/bin"
	echo -e "#!/bin/sh\nexec nw ${PREFIX}/lib/${PKGNAME}" \
		> "${DESTDIR}/${PREFIX}/bin/${PKGNAME}"
	chmod 0755 "${DESTDIR}/${PREFIX}/bin/${PKGNAME}"
	
	install -d "${DESTDIR}/${PREFIX}/lib/${PKGNAME}"
	cp -r ${APPCONTENT} "${DESTDIR}/${PREFIX}/lib/${PKGNAME}/"
	
	find "${DESTDIR}/${PREFIX}/lib/${PKGNAME}/" \
		-type d -exec chmod 0755 {} \;
	find "${DESTDIR}/${PREFIX}/lib/${PKGNAME}/" \
		-type f -exec chmod 0644 {} \;
	
	cp --preserve=mode -r node_modules "${DESTDIR}/${PREFIX}/lib/${PKGNAME}/"
	
	install -D -m644 support/linux/${PKGNAME}.desktop \
		"${DESTDIR}/${PREFIX}/share/applications/${PKGNAME}.desktop"
	
	install -D -m644 LICENSE "${DESTDIR}/${PREFIX}/share/licenses/${PKGNAME}"
	
	for size in ${LINUX_ICON_SIZES}; do \
		install -D -m644 support/linux/icons/$$size/${PKGNAME}.png \
			"${DESTDIR}/${PREFIX}/share/icons/hicolor/$$size/${PKGNAME}.png"; \
	done
	
	install -D -m644 support/linux/icons/scalable/${PKGNAME}.svg \
		"${DESTDIR}/${PREFIX}/share/icons/hicolor/scalable/${PKGNAME}.svg"

# Additional tasks

run: run-${OS}

run-Windows_NT:

run-Darwin: build/osx/Epsilon.app
	open build/osx/Epsilon.app

run-Linux: ${APPFILES}
	nw .

clean:
	rm -r build

clean-deps:
	rm -r node_modules

clean-cache:
	rm -r cache

clean-all: clean clean-deps clean-cache

.PHONY: all clean clean-deps clean-cache clean-all run-Windows_NT \
	run-Darwin run-Linux install install-Linux
