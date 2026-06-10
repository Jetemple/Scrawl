PREFIX ?= $(HOME)/Applications
BUILD_CONFIG ?= release
BUILD_ARCHS ?=
APP_NAME := Scrawl
APP_BUNDLE := $(APP_NAME).app
EXECUTABLE_TARGET := ScrawlApp
SWIFT_ARCH_FLAGS := $(foreach arch,$(BUILD_ARCHS),--arch $(arch))

.PHONY: build install uninstall clean test run run-debug check-deps doctor

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

run:
	./scripts/run-local.sh

run-debug:
	./scripts/run-local.sh --debug

install: build
	SCRAWL_SKIP_BUILD=1 SCRAWL_BUILD_CONFIGURATION="$(BUILD_CONFIG)" SCRAWL_BUILD_ARCHS="$(BUILD_ARCHS)" ./scripts/install-app.sh "$(PREFIX)"

uninstall:
	rm -rf "$(PREFIX)/$(APP_BUNDLE)"
	@echo "Removed $(PREFIX)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build/install
