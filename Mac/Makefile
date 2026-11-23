.PHONY: build test package clean

build:
	swift build --configuration release

test:
	bash scripts/test-models.sh

package:
	bash scripts/package-app.sh

clean:
	swift package clean
