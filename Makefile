# Device builds need the team in the generated project, not just on the command line (C-58).
# Supply it from the environment so the ID is never committed:
#     DEVELOPMENT_TEAM=XXXXXXXXXX make device
export DEVELOPMENT_TEAM ?=

APP := KeyboardProject
SCHEME := KeyboardProject
CONFIG ?= Debug
SIM_DESTINATION ?= generic/platform=iOS Simulator
# Override when a specific simulator is required. By default, select a booted iPhone or the
# newest available iPhone by UDID; model names vary between local and CI runtimes.
TEST_DESTINATION ?= platform=iOS Simulator,id=$(shell ./Scripts/select-simulator.sh)
DEVICE_ID ?=
DEVICE_DERIVED_DATA ?= $(CURDIR)/.build/device

.PHONY: bootstrap generate build test build-device install-device launch-device deploy-device device redeploy clean

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	xcodegen generate

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(APP).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-sdk iphonesimulator \
		-destination "$(SIM_DESTINATION)" \
		CODE_SIGNING_ALLOWED=NO \
		build

test: generate
	xcodebuild test -project $(APP).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination "$(TEST_DESTINATION)" \
		-parallel-testing-enabled NO \
		CODE_SIGNING_ALLOWED=NO

build-device:
	KB_ACTION=build KB_DEVICE_ID="$(DEVICE_ID)" KB_DERIVED_DATA="$(DEVICE_DERIVED_DATA)" \
		CONFIGURATION="$(CONFIG)" ./Scripts/redeploy.sh

install-device:
	KB_ACTION=install KB_DEVICE_ID="$(DEVICE_ID)" KB_DERIVED_DATA="$(DEVICE_DERIVED_DATA)" \
		CONFIGURATION="$(CONFIG)" ./Scripts/redeploy.sh

launch-device:
	KB_ACTION=launch KB_DEVICE_ID="$(DEVICE_ID)" KB_DERIVED_DATA="$(DEVICE_DERIVED_DATA)" \
		CONFIGURATION="$(CONFIG)" ./Scripts/redeploy.sh

deploy-device:
	KB_ACTION=deploy KB_DEVICE_ID="$(DEVICE_ID)" KB_DERIVED_DATA="$(DEVICE_DERIVED_DATA)" \
		CONFIGURATION="$(CONFIG)" ./Scripts/redeploy.sh

device: build-device

redeploy: deploy-device

clean:
	rm -rf -- "$(CURDIR)/$(APP).xcodeproj" "$(CURDIR)/.build"
