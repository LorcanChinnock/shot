# Every build goes through scripts/xcodebuild.sh, which builds Shot.xcodeproj into build/DerivedData.

# Extra xcodebuild arguments, e.g. ARGS=-quiet.
ARGS ?=
# One suite or test, e.g. ONLY=ShotCoreTests/GIFEncoderTests or ONLY='ShotCoreTests/hitTestFilledKinds()'.
ONLY ?=
# CI builds the tests in one step and runs them in the next, with TEST_ACTION=test-without-building.
TEST_ACTION ?= test
XCODEBUILD := scripts/xcodebuild.sh
DESTINATION := -destination 'platform=macOS,arch=$(shell uname -m)'

.PHONY: build build-tests test test-install test-uninstall perf-app lint strings bundle run stop demo dist reset-tcc icon clean

build:
	$(XCODEBUILD) -scheme Shot -configuration Debug $(DESTINATION) -quiet build $(ARGS)

# Not -quiet: with it, Xcode 27 reports some test files that compiled fine as failed "with exit code 0".
build-tests:
	$(XCODEBUILD) -scheme Shot $(DESTINATION) build-for-testing $(ARGS)

test:
	$(XCODEBUILD) -scheme Shot $(DESTINATION) $(TEST_ACTION) $(if $(ONLY),-only-testing:'$(ONLY)') $(ARGS)

# Runs site/public/install.sh against a local folder standing in for the GitHub release.
test-install:
	scripts/test-install.sh

# Runs site/public/uninstall.sh against a fake home folder.
test-uninstall:
	scripts/test-uninstall.sh

perf-app: bundle
	scripts/perf.sh

# Also checks Resources/Localizable.xcstrings has every string the app shows.
lint:
	scripts/lint.sh
	$(MAKE) build
	scripts/strings.sh --check

# Adds new strings to Resources/Localizable.xcstrings and drops ones the source no longer uses.
strings: build
	scripts/strings.sh

bundle:
	scripts/bundle.sh

# Without Xcode open: a Debug build, as Xcode's Run makes, launched from build/DerivedData. Like Run, it first quits every
# other ShotDev and the installed Shot (scripts/dev.sh). Arguments for the app go in APP_ARGS, e.g.
# APP_ARGS="-AppleLanguages '(de)'".
APP_ARGS ?=
run:
	scripts/dev.sh run $(APP_ARGS)

# Quits ShotDev, however it started, and reopens the installed Shot if a run quit it.
stop:
	scripts/dev.sh stop

# Builds and opens the MugCo sample app (Samples/MugCo), a steady window to capture in QA runs and screenshots.
demo:
	scripts/demo.sh

dist: export SHOT_RELEASE = 1
dist: bundle
	ditto -c -k --keepParent build/Shot.app build/Shot.zip
	@echo "Wrote build/Shot.zip"

# Clears ShotDev's Screen Recording permission (Config/Shot.xcconfig gives it its own bundle ID), never the release's.
reset-tcc:
	tccutil reset ScreenCapture dev.lorcan.Shot.dev

icon:
	swift scripts/make-icon.swift .

clean:
	rm -rf build
