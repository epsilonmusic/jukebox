APPFILES = $(shell find app) node_modules package.json
APPNAME  = Epsilon

NWVERSION = v0.10.0
NWOSX     = node-webkit-${NWVERSION}-osx-ia32

ifneq (${OS},Windows_NT)
OS = $(shell uname -s)
endif

all: build/osx/${APPNAME}.app build/win/${APPNAME} build/linux32/${APPNAME}

# Final results

build/${APPNAME}.nw: ${APPFILES} | build
	rm -f build/${APPNAME}.nw
	zip -9r build/${APPNAME}.nw ${APPFILES}

build/osx/${APPNAME}.app: ${APPFILES} | cache/${NWOSX} build/osx
	rm -rf build/osx/${APPNAME}.app
	cp -r cache/${NWOSX}/node-webkit.app build/osx/${APPNAME}.app

	cp support/osx/Info.plist build/osx/${APPNAME}.app/Contents/
	cp support/osx/Epsilon.icns build/osx/${APPNAME}.app/Contents/Resources/

	mkdir build/osx/${APPNAME}.app/Contents/Resources/app.nw
	cp -r ${APPFILES} build/osx/${APPNAME}.app/Contents/Resources/app.nw/

build/win/${APPNAME}: build/${APPNAME}.nw | build/win

build/linux32/${APPNAME}: build/${APPNAME}.nw | build/linux32

build build/osx build/win build/linux32:
	mkdir -p $@

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

# Additional tasks

run: all run-${OS}

run-Windows_NT:

run-Darwin: build/osx/Epsilon.app
	open build/osx/Epsilon.app

run-Linux: build/Epsilon.nw
	nw build/Epsilon.nw

clean:
	rm -r build

clean-deps:
	rm -r node_modules

clean-cache:
	rm -r cache

clean-all: clean clean-deps clean-cache

.PHONY: all clean clean-deps clean-cache clean-all run-Windows_NT run-Darwin run-Linux
