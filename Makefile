PROJECT := Pasteup.xcodeproj
SCHEME := Pasteup
DERIVED := build/DerivedData
APP_NAME := Pasteup
DEBUG_APP := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
INSTALLED_APP := /Applications/$(APP_NAME).app

.PHONY: gen icons build release test install run clean promo-take promo-render bump-major bump-minor bump-patch

gen:
	xcodegen generate --quiet

# Update version/build, finalize Unreleased notes, and regenerate XcodeGen outputs.
bump-major bump-minor bump-patch:
	python3 Scripts/bump-version.py $(patsubst bump-%,%,$@)

# Regenerates the app icon and the menu bar icon in the asset catalog.
icons:
	swift -swift-version 5 Scripts/render-icons.swift Pasteup

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

release: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

test:
	cd Packages/PasteupCore && swift test

# Replaces the installed copy with a fresh Release build.
install: release
	pkill -x "$(APP_NAME)" || true
	rm -rf "$(INSTALLED_APP)"
	ditto "$(RELEASE_APP)" "$(INSTALLED_APP)"

run: install
	open "$(INSTALLED_APP)"

# Records a promo take on the built-in display (hands off the mouse and keyboard while it runs).
promo-take:
	Promo/take.sh

# Renders the promo videos and the README animation from the last take.
promo-render:
	Promo/compose.sh

clean:
	rm -rf build $(PROJECT)
