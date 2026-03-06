PREFIX ?= $(HOME)/Applications
BUILD_CONFIG ?= release
APP_NAME := Scrawl
APP_BUNDLE := $(APP_NAME).app
EXECUTABLE_TARGET := ScrawlApp

.PHONY: build install uninstall clean test check-deps

check-deps:
	@command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed. Install Xcode command line tools: xcode-select --install"; exit 1; }
	@command -v whisper-cli >/dev/null 2>&1 || { echo "Error: whisper-cli not found. Install it first: brew install whisper-cpp"; exit 1; }

build: check-deps
	swift build -c $(BUILD_CONFIG) --product $(EXECUTABLE_TARGET)

test:
	swift test

install: build
	SCRAWL_SKIP_BUILD=1 ./scripts/install-app.sh "$(PREFIX)"

uninstall:
	rm -rf "$(PREFIX)/$(APP_BUNDLE)"
	@echo "Removed $(PREFIX)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build/install
