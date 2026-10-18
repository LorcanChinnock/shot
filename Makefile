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

.PHONY: build test test-linux perf perf-app lint strings bundle app run dist release-gate reset-tcc icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(ARGS) --skip PerfTests

# ShotModel's tests on Linux, as CI's linux job runs them. Needs Docker; keep the image in step with ci.yml.
test-linux:
	docker run --rm -v "$(CURDIR)":/src -w /src swift:6.3 swift test --scratch-path .build/linux

# Budgets and baselines: docs/performance.md.
perf:
	swift test $(TEST_FLAGS) $(ARGS) --filter PerfTests

perf-app:
	scripts/perf.sh

# On a Mac, also checks Resources/Localizable.xcstrings has every string the app shows; CI's linux job can't.
lint:
	scripts/lint.sh
ifeq ($(shell uname),Darwin)
	swift build
	scripts/strings.sh --check
endif

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

dist: export SHOT_RELEASE = 1
dist: bundle
	ditto -c -k --keepParent build/Shot.app build/Shot.zip
	@echo "Wrote build/Shot.zip"

# Runs CI's macOS gate on the release PR, which can't merge without it. release.yml runs it each time release-please
# opens or updates the PR, so this is for re-running it by hand. See .github/workflows/ci.yml.
release-gate:
	gh workflow run ci.yml --ref release-please--branches--main--components--Shot -f gate=true

# Clears ShotDev's permission (scripts/bundle.sh gives dev builds the release ID plus .dev), never the release's.
reset-tcc:
	tccutil reset ScreenCapture $$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist).dev

icon:
	swift scripts/make-icon.swift .

clean:
	rm -rf .build build
