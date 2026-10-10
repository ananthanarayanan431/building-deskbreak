.PHONY: build app test clean

# With only the Command Line Tools installed, SwiftPM needs explicit paths to the Testing framework.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

build:
	swift build

app:
	scripts/build-app.sh

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
