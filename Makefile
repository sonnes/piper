APP := build/Piper.app
.DEFAULT_GOAL := build
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
ARCH := $(shell uname -m)
DMG := build/Piper_$(VERSION)_$(ARCH).dmg

.PHONY: build run test signed-app signed-dmg release

Resources/Piper.icns: Resources/AppIcon.png
	mkdir -p build/Piper.iconset
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $< --out build/Piper.iconset/icon_$${size}x$${size}.png >/dev/null; \
		doubled=$$((size * 2)); \
		sips -z $$doubled $$doubled $< --out build/Piper.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/Piper.iconset -o $@

build: Resources/Piper.icns
	swift build --product Piper
	mkdir -p build/Piper.app/Contents/MacOS
	cp .build/debug/Piper build/Piper.app/Contents/MacOS/Piper
	cp Info.plist build/Piper.app/Contents/Info.plist
	mkdir -p build/Piper.app/Contents/Resources/Licenses
	cp -f Licenses/*.txt build/Piper.app/Contents/Resources/Licenses/
	cp Resources/PrivacyInfo.xcprivacy build/Piper.app/Contents/Resources/
	cp Resources/Piper.icns build/Piper.app/Contents/Resources/
	ditto .build/debug/Piper_Piper.bundle build/Piper.app/Contents/Resources/Piper_Piper.bundle
	codesign --force --sign - build/Piper.app

run: build
	open build/Piper.app

test:
	swift test

signed-app: Resources/Piper.icns
	@: "$${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY}"
	swift build -c release --product Piper
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	ditto .build/release/Piper "$(APP)/Contents/MacOS/Piper"
	ditto Info.plist "$(APP)/Contents/Info.plist"
	mkdir -p "$(APP)/Contents/Resources/Licenses"
	ditto Licenses "$(APP)/Contents/Resources/Licenses"
	ditto Resources/PrivacyInfo.xcprivacy "$(APP)/Contents/Resources/PrivacyInfo.xcprivacy"
	ditto Resources/Piper.icns "$(APP)/Contents/Resources/Piper.icns"
	ditto .build/release/Piper_Piper.bundle "$(APP)/Contents/Resources/Piper_Piper.bundle"
	codesign --force --sign "$${APPLE_SIGNING_IDENTITY}" --options runtime --timestamp "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"

signed-dmg: signed-app
	@set -eu; \
	dmg_staging="$$(mktemp -d "build/dmg.XXXXXX")"; \
	trap 'rm -rf "$$dmg_staging"' EXIT; \
	ditto "$(APP)" "$$dmg_staging/Piper.app"; \
	ln -s /Applications "$$dmg_staging/Applications"; \
	rm -f "$(DMG)"; \
	hdiutil create -volname Piper -srcfolder "$$dmg_staging" -ov -format UDZO "$(DMG)"; \
	codesign --force --sign "$${APPLE_SIGNING_IDENTITY}" --timestamp "$(DMG)"; \
	codesign --verify --verbose=2 "$(DMG)"

# Build, notarize, staple, and validate the direct-download DMG.
release: test
	@set -eu; \
	test -f .envrc || { echo "Missing .envrc in the repository root"; exit 1; }; \
	. ./.envrc; \
	: "$${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .envrc}"; \
	: "$${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY in .envrc}"; \
	: "$${APPLE_API_ISSUER:?Set APPLE_API_ISSUER in .envrc}"; \
	: "$${APPLE_API_KEY:?Set APPLE_API_KEY in .envrc}"; \
	: "$${APPLE_API_KEY_PATH:?Set APPLE_API_KEY_PATH in .envrc}"; \
	test -r "$${APPLE_API_KEY_PATH}" || { echo "Cannot read APPLE_API_KEY_PATH"; exit 1; }; \
	$(MAKE) signed-dmg APPLE_SIGNING_IDENTITY="$${APPLE_SIGNING_IDENTITY}"; \
	xcrun notarytool submit "$(DMG)" \
		--key "$${APPLE_API_KEY_PATH}" \
		--key-id "$${APPLE_API_KEY}" \
		--issuer "$${APPLE_API_ISSUER}" \
		--wait; \
	xcrun stapler staple "$(DMG)"; \
	xcrun stapler validate "$(DMG)"; \
	spctl --assess --type open --context context:primary-signature --verbose=4 "$(DMG)"; \
	shasum -a 256 "$(DMG)"
