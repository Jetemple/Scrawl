PREFIX ?= $(HOME)/Applications
BUILD_CONFIG ?= release
APP_NAME := Scrawl
APP_BUNDLE := $(APP_NAME).app
EXECUTABLE_TARGET := ScrawlApp

.PHONY: build install uninstall clean test

build:
	swift build -c $(BUILD_CONFIG) --product $(EXECUTABLE_TARGET)

test:
	swift test

install: build
	./scripts/install-app.sh "$(PREFIX)"

uninstall:
	rm -rf "$(PREFIX)/$(APP_BUNDLE)"
	@echo "Removed $(PREFIX)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build/install
