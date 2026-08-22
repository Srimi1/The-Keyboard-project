APP := KeyboardProject
SCHEME := KeyboardProject
CONFIG ?= Debug
SIM_DESTINATION ?= 'generic/platform=iOS Simulator'
TEST_DESTINATION ?= 'platform=iOS Simulator,name=iPhone 17'

.PHONY: bootstrap generate build test redeploy clean

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	xcodegen generate

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(APP).xcodeproj \
		-scheme $(SCHEME) \
		-sdk iphonesimulator \
		-destination $(SIM_DESTINATION) \
		CODE_SIGNING_ALLOWED=NO \
		build

test: generate
	xcodebuild test -project $(APP).xcodeproj \
		-scheme $(SCHEME) \
		-destination $(TEST_DESTINATION) \
		CODE_SIGNING_ALLOWED=NO

redeploy:
	@chmod +x ./Scripts/redeploy.sh 2>/dev/null || true
	./Scripts/redeploy.sh

clean:
	rm -rf $(APP).xcodeproj
	rm -rf ~/Library/Developer/Xcode/DerivedData/KeyboardProject-*
