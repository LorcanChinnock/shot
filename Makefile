# Building with only the Command Line Tools: their default SDK (27) makes SwiftUI's @State a
# macro whose compiler plugin ships with Xcode alone, so pin the 26.5 SDK when it's there.
# With Xcode selected, the default SDK works and nothing is pinned.
CLT_SDK := /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
ifeq ($(findstring CommandLineTools,$(shell xcode-select -p)),CommandLineTools)
ifneq ($(wildcard $(CLT_SDK)),)
export SDKROOT ?= $(CLT_SDK)
endif
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
endif

INSTALL_DIR ?= /Applications

.PHONY: build test bundle app run dist reset-tcc icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

bundle:
	scripts/bundle.sh

app: bundle
	scripts/install.sh "$(INSTALL_DIR)"

run: app
	pkill -f "Shot Dev.app/Contents/MacOS/Shot" || true
	open "$(INSTALL_DIR)/Shot Dev.app"

dist: export SHOT_ARCHS ?= arm64 x86_64
dist: export SHOT_VARIANT = release
dist: bundle
	ditto -c -k --keepParent build/Shot.app build/Shot.zip
	@echo "Wrote build/Shot.zip"

reset-tcc:
	tccutil reset ScreenCapture $$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist).dev

icon:
	swift scripts/make-icon.swift .

clean:
	rm -rf .build build
