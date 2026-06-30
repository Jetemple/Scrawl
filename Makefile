PREFIX ?= $(HOME)/Applications
BUILD_CONFIG ?= release
BUILD_ARCHS ?=
SNAPSHOT_DIR ?= /tmp/scrawl-models
SNAPSHOT_PREFERENCES_DIR ?= /tmp/scrawl-preferences
APP_NAME := Scrawl
APP_BUNDLE := $(APP_NAME).app
EXECUTABLE_TARGET := ScrawlApp
SWIFT_ARCH_FLAGS := $(foreach arch,$(BUILD_ARCHS),--arch $(arch))

.PHONY: build install uninstall clean test coverage lint format format-check run run-debug snapshots-models snapshots-preferences check-deps doctor

check-deps:
	@command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed. Install Xcode command line tools: xcode-select --install"; exit 1; }
	@command -v whisper-cli >/dev/null 2>&1 || { echo "Error: whisper-cli not found. Install it first: brew install whisper-cpp"; exit 1; }

doctor:
	@echo "Project: $(APP_NAME)"
	@echo "Swift: $$(swift --version | head -n 1)"
	@echo "whisper-cli: $$(command -v whisper-cli)"
	@echo "Install prefix: $(PREFIX)"

build: check-deps
	swift build -c $(BUILD_CONFIG) $(SWIFT_ARCH_FLAGS) --product $(EXECUTABLE_TARGET)

test:
	swift test

coverage:
	swift test --enable-code-coverage
	@bin=$$(swift build --show-bin-path); \
	xctest=$$(find "$$bin" -maxdepth 1 -name '*.xctest' | head -1); \
	name=$$(basename "$$xctest" .xctest); \
	xcrun llvm-cov export -format=lcov "$$xctest/Contents/MacOS/$$name" \
		-instr-profile "$$bin/codecov/default.profdata" \
		-ignore-filename-regex='(Tests|\.build)' > coverage.lcov; \
	echo "Wrote coverage.lcov ($$(wc -l < coverage.lcov) lines)"

lint:
	@command -v swiftlint >/dev/null 2>&1 || { echo "Error: swiftlint not installed. Run: brew install swiftlint"; exit 1; }
	swiftlint lint --quiet

format:
	@command -v swiftformat >/dev/null 2>&1 || { echo "Error: swiftformat not installed. Run: brew install swiftformat"; exit 1; }
	swiftformat Sources Tests

format-check:
	@command -v swiftformat >/dev/null 2>&1 || { echo "Error: swiftformat not installed. Run: brew install swiftformat"; exit 1; }
	swiftformat Sources Tests --lint

run:
	./scripts/run-local.sh

run-debug:
	./scripts/run-local.sh --debug

snapshots-models:
	rm -rf "$(SNAPSHOT_DIR)"
	SCRAWL_SNAPSHOT_DIR="$(SNAPSHOT_DIR)" swift test --filter PreferencesModelsViewSnapshotTests
	open "$(SNAPSHOT_DIR)"

snapshots-preferences:
	rm -rf "$(SNAPSHOT_PREFERENCES_DIR)"
	SCRAWL_PREFERENCES_SNAPSHOT_DIR="$(SNAPSHOT_PREFERENCES_DIR)" swift test --filter PreferencesWindowSnapshotTests
	open "$(SNAPSHOT_PREFERENCES_DIR)"

install: build
	SCRAWL_SKIP_BUILD=1 SCRAWL_BUILD_CONFIGURATION="$(BUILD_CONFIG)" SCRAWL_BUILD_ARCHS="$(BUILD_ARCHS)" ./scripts/install-app.sh "$(PREFIX)"

uninstall:
	rm -rf "$(PREFIX)/$(APP_BUNDLE)"
	@echo "Removed $(PREFIX)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build/install
