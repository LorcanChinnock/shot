# CLT's default SDK (27) makes SwiftUI @State a macro whose plugin ships only with Xcode.
export SDKROOT ?= /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing

.PHONY: build test app run reset-tcc

build:
	swift build

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)

app:
	scripts/bundle.sh

run: app
	pkill -x Shot || true
	open ~/Applications/Shot.app

reset-tcc:
	tccutil reset ScreenCapture dev.lorcan.Shot
