APPNAME    = Epsilon
PKGNAME    = epsilon-jukebox

APPCONTENT = app package.json LICENSE README.md
APPFILES   = $(shell find app -type f -print) package.json LICENSE README.md
APPVERSION = 0.0.1

NWVERSION  = v0.10.1
NWOSX      = node-webkit-${NWVERSION}-osx-ia32
NWWIN      = node-webkit-${NWVERSION}-win-ia32

PREFIX     = /usr/local
DESTDIR    =

ifneq (${OS},Windows_NT)
OS = $(shell uname -s)
endif

LINUX_ICON_SIZES = 16x16 32x32 48x48 384x384

all: build/osx/${APPNAME}.app build/win/${APPNAME}

# Dependencies

cache/${NWOSX}: | cache
	cd cache && \
	curl -o ${NWOSX}.zip \
		"http://dl.node-webkit.org/${NWVERSION}/${NWOSX}.zip" && \
	unzip ${NWOSX}.zip

cache/${NWWIN}: | cache
	cd cache && \
	curl -o ${NWWIN}.zip \
		"http://dl.node-webkit.org/${NWVERSION}/${NWWIN}.zip" && \
	unzip ${NWWIN}.zip

cache:
	mkdir -p $@

node_modules: package.json
	npm install

# Final results

build/osx/${APPNAME}.app: ${APPFILES} \
		support/osx/Info.plist support/osx/${APPNAME}.icns \
		| cache/${NWOSX} build/osx

	rm -rf build/osx/${APPNAME}.app
	cp -r cache/${NWOSX}/node-webkit.app build/osx/${APPNAME}.app

	cp support/osx/Info.plist build/osx/${APPNAME}.app/Contents/
	cp support/osx/${APPNAME}.icns build/osx/${APPNAME}.app/Contents/Resources/

	mkdir build/osx/${APPNAME}.app/Contents/Resources/app.nw
	cp -r ${APPCONTENT} build/osx/${APPNAME}.app/Contents/Resources/app.nw/

	cd build/osx/${APPNAME}.app/Contents/Resources/app.nw && \
		npm install --production

build/win/${APPNAME}: node_modules ${APPFILES} \
		support/win/set-resources.js support/win/${APPNAME}.ico \
		| cache/${NWWIN} build/win

	rm -rf build/win/${APPNAME}
	cp -r cache/${NWWIN} build/win/${APPNAME}

	rm build/win/${APPNAME}/nwsnapshot.exe
	mv build/win/${APPNAME}/{,nw-}credits.html
	mv build/win/${APPNAME}/{nw,${APPNAME}}.exe

	node support/win/set-resources.js \
		build/win/${APPNAME}/${APPNAME}.exe \
		support/win/${APPNAME}.ico

	cp -r ${APPCONTENT} build/win/${APPNAME}/

	cd build/win/${APPNAME} && \
		npm install --production

build build/osx build/win:
	mkdir -p $@

# Installation

install: install-${OS}

install-Linux: ${APPFILES} support/linux/${PKGNAME}.desktop
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
	
	cd "${DESTDIR}/${PREFIX}/lib/${PKGNAME}/" && \
		npm install --production
	
	install -D -m644 support/linux/${PKGNAME}.desktop \
		"${DESTDIR}/${PREFIX}/share/applications/${PKGNAME}.desktop"
	
	install -D -m644 LICENSE "${DESTDIR}/${PREFIX}/share/licenses/${PKGNAME}"
	
	for size in ${LINUX_ICON_SIZES}; do \
		install -D -m644 support/linux/icons/$$size/apps/${PKGNAME}.png \
			"${DESTDIR}/${PREFIX}/share/icons/hicolor/$$size/apps/${PKGNAME}.png"; \
	done
	
	install -D -m644 support/linux/icons/scalable/apps/${PKGNAME}.svg \
		"${DESTDIR}/${PREFIX}/share/icons/hicolor/scalable/apps/${PKGNAME}.svg"

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
