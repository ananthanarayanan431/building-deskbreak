.PHONY: build app test clean

build:
	swift build

app:
	scripts/build-app.sh

test:
	swift test

clean:
	rm -rf .build build
