# Makefile for UIColorPalette iOS project
# Supports iOS, iOS Simulator, and Mac Catalyst builds

# Project configuration
PROJECT_NAME = UIColorPalette
BUNDLE_ID = com.example.UIColorPalette
SOURCE_DIR = UIColorPalette
BUILD_DIR = build
DIST_DIR = dist

# Source files
SOURCES = $(SOURCE_DIR)/main.m \
          $(SOURCE_DIR)/AppDelegate.m \
          $(SOURCE_DIR)/ViewController.m

HEADERS = $(SOURCE_DIR)/AppDelegate.h \
          $(SOURCE_DIR)/ViewController.h

# Resources
INFO_PLIST = $(SOURCE_DIR)/Info.plist
ENTITLEMENTS = $(SOURCE_DIR)/UIColorPalette.entitlements
ICON_FILE = $(SOURCE_DIR)/AppIcon.png

# Environment variable overrides with defaults
ifneq ($(shell which xcrun 2>/dev/null),)
    CC ?= $(shell xcrun -f clang)
    IOS_SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
    IOS_SIM_SDK ?= $(shell xcrun --sdk iphonesimulator --show-sdk-path)
    MACOS_SDK ?= $(shell xcrun --sdk macosx --show-sdk-path)
else
    CC ?= clang
    IOS_SDK ?= /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
    IOS_SIM_SDK ?= /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
    MACOS_SDK ?= /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
endif

# Common compiler flags
COMMON_FLAGS = -fobjc-arc -fmodules \
               -I$(SOURCE_DIR) \
               -framework Foundation -framework UIKit -framework QuartzCore -framework Metal

# Architecture handling
USE_LIPO ?= 1

ifdef ARCH
    IOS_ARCHS = $(ARCH)
    SIM_ARCHS = $(ARCH) 
    CATALYST_ARCHS = $(ARCH)
    USE_LIPO = 0
else
    ifeq ($(USE_LIPO), 0)
        # If USE_LIPO is 0 and ARCH is unset, default to arm64
        IOS_ARCHS = arm64
        SIM_ARCHS = arm64
        CATALYST_ARCHS = arm64
    else
        IOS_ARCHS = arm64
        SIM_ARCHS = x86_64 arm64
        CATALYST_ARCHS = x86_64 arm64
    endif
endif

# Targets
.PHONY: all ios iossim catalyst clean

all: ios iossim catalyst

# iOS build (produces IPA)
ios: $(DIST_DIR)/$(PROJECT_NAME).ipa

$(DIST_DIR)/$(PROJECT_NAME).ipa: $(BUILD_DIR)/ios/$(PROJECT_NAME).app
	@echo "Creating IPA package..."
	@mkdir -p $(DIST_DIR)
	@mkdir -p $(BUILD_DIR)/ios-package/Payload
	@cp -r $(BUILD_DIR)/ios/$(PROJECT_NAME).app $(BUILD_DIR)/ios-package/Payload/
	@cd $(BUILD_DIR)/ios-package && zip -r ../../$(DIST_DIR)/$(PROJECT_NAME).ipa Payload
	@echo "IPA created at $(DIST_DIR)/$(PROJECT_NAME).ipa"

$(BUILD_DIR)/ios/$(PROJECT_NAME).app: $(BUILD_DIR)/ios/$(PROJECT_NAME)
	@echo "Creating iOS app bundle..."
	@mkdir -p $(BUILD_DIR)/ios/$(PROJECT_NAME).app
	@cp $(BUILD_DIR)/ios/$(PROJECT_NAME) $(BUILD_DIR)/ios/$(PROJECT_NAME).app/
	@cp $(INFO_PLIST) $(BUILD_DIR)/ios/$(PROJECT_NAME).app/Info.plist
	@if [ -f $(ICON_FILE) ]; then cp $(ICON_FILE) $(BUILD_DIR)/ios/$(PROJECT_NAME).app/; fi
	@echo "iOS app bundle created"

$(BUILD_DIR)/ios/$(PROJECT_NAME): $(SOURCES)
	@echo "Building for iOS..."
	@mkdir -p $(BUILD_DIR)/ios
ifeq ($(USE_LIPO), 1)
	@for arch in $(IOS_ARCHS); do \
		echo "Building iOS $$arch..."; \
		$(CC) -target $$arch-apple-ios14.0 \
		      -isysroot $(IOS_SDK) \
		      -mios-version-min=14.0 \
		      $(COMMON_FLAGS) \
		      -o $(BUILD_DIR)/ios/$(PROJECT_NAME).$$arch \
		      $(SOURCES); \
	done
	@echo "Creating universal binary..."
	@lipo -create $(foreach arch,$(IOS_ARCHS),$(BUILD_DIR)/ios/$(PROJECT_NAME).$(arch)) -output $@
	@rm -f $(foreach arch,$(IOS_ARCHS),$(BUILD_DIR)/ios/$(PROJECT_NAME).$(arch))
else
	@echo "Building iOS $(ARCH)..."
	@$(CC) -target $(ARCH)-apple-ios14.0 \
	       -isysroot $(IOS_SDK) \
	       -mios-version-min=14.0 \
	       $(COMMON_FLAGS) \
	       -o $@ \
	       $(SOURCES)
endif

# iOS Simulator build
iossim: $(BUILD_DIR)/iossim/$(PROJECT_NAME).app

$(BUILD_DIR)/iossim/$(PROJECT_NAME).app: $(BUILD_DIR)/iossim/$(PROJECT_NAME)
	@echo "Creating iOS Simulator app bundle..."
	@mkdir -p $(BUILD_DIR)/iossim/$(PROJECT_NAME).app
	@cp $(BUILD_DIR)/iossim/$(PROJECT_NAME) $(BUILD_DIR)/iossim/$(PROJECT_NAME).app/
	@cp $(INFO_PLIST) $(BUILD_DIR)/iossim/$(PROJECT_NAME).app/Info.plist
	@if [ -f $(ICON_FILE) ]; then cp $(ICON_FILE) $(BUILD_DIR)/iossim/$(PROJECT_NAME).app/; fi
	@echo "iOS Simulator app bundle created at $(BUILD_DIR)/iossim/$(PROJECT_NAME).app"

$(BUILD_DIR)/iossim/$(PROJECT_NAME): $(SOURCES)
	@echo "Building for iOS Simulator..."
	@mkdir -p $(BUILD_DIR)/iossim
ifeq ($(USE_LIPO), 1)
	@for arch in $(SIM_ARCHS); do \
		echo "Building iOS Simulator $$arch..."; \
		$(CC) -target $$arch-apple-ios14.0-simulator \
		      -isysroot $(IOS_SIM_SDK) \
		      -mios-simulator-version-min=14.0 \
		      $(COMMON_FLAGS) \
		      -o $(BUILD_DIR)/iossim/$(PROJECT_NAME).$$arch \
		      $(SOURCES); \
	done
	@echo "Creating universal binary..."
	@lipo -create $(foreach arch,$(SIM_ARCHS),$(BUILD_DIR)/iossim/$(PROJECT_NAME).$(arch)) -output $@
	@rm -f $(foreach arch,$(SIM_ARCHS),$(BUILD_DIR)/iossim/$(PROJECT_NAME).$(arch))
else
	@echo "Building iOS Simulator $(ARCH)..."
	@$(CC) -target $(ARCH)-apple-ios14.0-simulator \
	       -isysroot $(IOS_SIM_SDK) \
	       -mios-simulator-version-min=14.0 \
	       $(COMMON_FLAGS) \
	       -o $@ \
	       $(SOURCES)
endif

# Mac Catalyst build
catalyst: $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app

$(BUILD_DIR)/catalyst/$(PROJECT_NAME).app: $(BUILD_DIR)/catalyst/$(PROJECT_NAME)
	@echo "Creating Mac Catalyst app bundle..."
	@mkdir -p $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/Resources
	@cp $(BUILD_DIR)/catalyst/$(PROJECT_NAME) $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/MacOS/
	@cp $(INFO_PLIST) $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/Info.plist
	@if [ -f $(ICON_FILE) ]; then cp $(ICON_FILE) $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/Resources/; fi
	# Update Info.plist for Mac Catalyst
	@if command -v plutil >/dev/null 2>&1; then \
		plutil -replace CFBundlePackageType -string "APPL" $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/Info.plist; \
		plutil -replace LSMinimumSystemVersion -string "11.0" $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app/Contents/Info.plist; \
	fi
	@if command -v codesign >/dev/null 2>&1; then \
		echo "Code signing Mac Catalyst app..."; \
		codesign -f -s - --entitlements $(ENTITLEMENTS) --deep $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app; \
	else \
		echo "codesign not found, skipping code signing"; \
	fi
	@echo "Mac Catalyst app bundle created at $(BUILD_DIR)/catalyst/$(PROJECT_NAME).app"

$(BUILD_DIR)/catalyst/$(PROJECT_NAME): $(SOURCES)
	@echo "Building for Mac Catalyst..."
	@mkdir -p $(BUILD_DIR)/catalyst
ifeq ($(USE_LIPO), 1)
	@for arch in $(CATALYST_ARCHS); do \
		echo "Building Mac Catalyst $$arch..."; \
		$(CC) -target $$arch-apple-ios14.0-macabi \
		      -isysroot $(MACOS_SDK) \
		      -mmacosx-version-min=11.0 \
		      $(COMMON_FLAGS) \
		      -DTARGET_OS_MACCATALYST=1 \
		      -o $(BUILD_DIR)/catalyst/$(PROJECT_NAME).$$arch \
		      $(SOURCES); \
	done
	@echo "Creating universal binary..."
	@lipo -create $(foreach arch,$(CATALYST_ARCHS),$(BUILD_DIR)/catalyst/$(PROJECT_NAME).$(arch)) -output $@
	@rm -f $(foreach arch,$(CATALYST_ARCHS),$(BUILD_DIR)/catalyst/$(PROJECT_NAME).$(arch))
else
	@echo "Building Mac Catalyst $(ARCH)..."
	@$(CC) -target $(ARCH)-apple-ios14.0-macabi \
	       -isysroot $(MACOS_SDK) \
	       -mmacosx-version-min=11.0 \
	       $(COMMON_FLAGS) \
	       -DTARGET_OS_MACCATALYST=1 \
	       -o $@ \
	       $(SOURCES)
endif

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "Clean complete"

# Help target
help:
	@echo "Available targets:"
	@echo "  ios       - Build iOS app and create IPA (arm64, iOS 14.0+)"
	@echo "  iossim    - Build iOS Simulator app (x86_64+arm64, iOS 14.0+)"
	@echo "  catalyst  - Build Mac Catalyst app (x86_64+arm64, macOS 11.0+)"
	@echo "  clean     - Clean all build artifacts"
	@echo "  all       - Build all targets"
	@echo ""
	@echo "Environment variables:"
	@echo "  ARCH      - Build for single architecture instead of universal binary"
	@echo ""
	@echo "Examples:"
	@echo "  make ios                    # Universal iOS build"
	@echo "  ARCH=arm64 make iossim      # Single-arch iOS simulator build"
	@echo "  make catalyst               # Universal Mac Catalyst build"
