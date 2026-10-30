# Building with only the Command Line Tools: their default SDK (27) makes SwiftUI's @State a
# macro whose compiler plugin ships with Xcode alone, so pin the newest 26.x SDK when there is one.
# With Xcode selected, the default SDK works and nothing is pinned.
CLT_SDK := $(lastword $(sort $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk)))
ifeq ($(findstring CommandLineTools,$(shell xcode-select -p)),CommandLineTools)
ifneq ($(wildcard $(CLT_SDK)),)
export SDKROOT ?= $(CLT_SDK)
endif
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
endif

INSTALL_DIR ?= /Applications
# Extra `swift test` flags, e.g. ARGS=--skip-build in CI.
ARGS ?=

.PHONY: build test perf-app lint strings bundle app run demo dist reset-tcc icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(ARGS)

perf-app:
	scripts/perf.sh

# Also checks Resources/Localizable.xcstrings has every string the app shows.
lint:
	scripts/lint.sh
	swift build
	scripts/strings.sh --check

# Adds new strings to Resources/Localizable.xcstrings and drops ones the source no longer uses.
strings:
	swift build
	scripts/strings.sh

bundle:
	scripts/bundle.sh

app: bundle
	scripts/install.sh "$(INSTALL_DIR)"

run: app
	pkill -x ShotDev || true
	while pgrep -x ShotDev >/dev/null; do sleep 0.1; done
	open "$(INSTALL_DIR)/ShotDev.app"

# Builds and opens the MugCo sample app (Samples/MugCo), a steady window to capture in QA runs and screenshots.
demo:
	scripts/demo.sh

dist: export SHOT_RELEASE = 1
dist: bundle
	ditto -c -k --keepParent build/Shot.app build/Shot.zip
	@echo "Wrote build/Shot.zip"

# Clears ShotDev's permission (scripts/bundle.sh gives dev builds the release ID plus .dev), never the release's.
reset-tcc:
	tccutil reset ScreenCapture $$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist).dev

icon:
	swift scripts/make-icon.swift .

clean:
	rm -rf .build build
